import json
import logging
import os
import time
from datetime import UTC, datetime
from decimal import Decimal

import boto3
from botocore.exceptions import ClientError

DIAS_DE_RETENCION = 90
SEGUNDOS_POR_DIA = 86400


class ValidationError(Exception):
    """Mensaje que ningun reintento va a arreglar: se descarta hacia la DLQ."""


class JsonFormatter(logging.Formatter):
    def format(self, record):
        payload = {
            "level": record.levelname,
            "message": record.getMessage(),
        }

        contexto = getattr(record, "context", None)
        if contexto is not None:
            payload["context"] = contexto

        if record.exc_info:
            payload["error"] = self.formatException(record.exc_info)

        return json.dumps(payload, ensure_ascii=False)


def _armar_logger():
    logger = logging.getLogger("processor")
    logger.setLevel(os.environ.get("LOG_LEVEL", "INFO").upper())

    # El runtime de Lambda instala su propio handler en el logger raiz con formato de
    # texto plano. Sin propagate en False cada linea sale dos veces, una en JSON y otra no.
    salida = logging.StreamHandler()
    salida.setFormatter(JsonFormatter())
    logger.handlers = [salida]
    logger.propagate = False

    return logger


log = _armar_logger()

_tabla = None


def get_table():
    # Perezoso y cacheado: el recurso sobrevive entre invocaciones del mismo contenedor,
    # asi que el costo de construirlo se paga una vez por arranque en frio y no en cada
    # mensaje. Construirlo al importar el modulo obligaria a tener credenciales validas
    # para poder importar el archivo en las pruebas unitarias.
    global _tabla

    if _tabla is None:
        _tabla = boto3.resource("dynamodb").Table(os.environ["TABLE_NAME"])

    return _tabla


def parse_record(record):
    try:
        cuerpo = json.loads(record["body"])
    except (KeyError, TypeError, ValueError) as exc:
        raise ValidationError("el cuerpo del mensage no es JSON valido") from exc

    detail = cuerpo.get("detail")

    if not isinstance(detail, dict):
        raise ValidationError("el evento no trae un detail de tipo objeto")

    return detail


def validate(detail):
    for campo in ("orderId", "customerId"):
        valor = detail.get(campo)

        if not isinstance(valor, str) or not valor.strip():
            raise ValidationError(f"falta el campo obligatorio {campo}")

    try:
        amount = float(detail["amount"])
    except (KeyError, TypeError, ValueError) as exc:
        raise ValidationError("amount no es un numero") from exc

    # Un importe negativo no es un error transitorio, pero tampoco algo que se pueda
    # ignorar en silencio: es el caso que empuja el mensaje hasta la DLQ y dispara la
    # alarma para que alguien mire de donde salio.
    if amount < 0:
        raise ValidationError("amount negativo")

    return amount


def store(detail, amount):
    ahora = int(time.time())

    item = {
        "orderId": detail["orderId"],
        # createdAt forma parte de la clave. Si el productor no lo manda, cada reentrega
        # genera una clave distinta y la escritura condicional deja de ser idempotente.
        "createdAt": detail.get("createdAt") or datetime.fromtimestamp(ahora, UTC).isoformat(),
        "customerId": detail["customerId"],
        # DynamoDB no acepta float: pierde precision al serializar. Decimal sobre la
        # representacion en texto conserva exactamente lo que llego en el evento.
        "amount": Decimal(str(amount)),
        "expiresAt": ahora + DIAS_DE_RETENCION * SEGUNDOS_POR_DIA,
    }

    try:
        get_table().put_item(
            Item=item,
            # SQS entrega al menos una vez. Sin esta condicion, un reintento del mismo
            # mensaje pisaria el item original y contaria el pedido dos veces.
            ConditionExpression="attribute_not_exists(orderId)",
        )
    except ClientError as exc:
        if exc.response["Error"]["Code"] == "ConditionalCheckFailedException":
            return "duplicado"
        raise

    return "creado"


def handler(event, context):
    fallidos = []

    for record in event.get("Records", []):
        message_id = record.get("messageId")

        try:
            detail = parse_record(record)
            amount = validate(detail)
            resultado = store(detail, amount)
        except ValidationError as exc:
            # Se loguea el motivo y el identificador, nunca el evento completo: el detail
            # trae datos del cliente y los logs se retienen y se comparten.
            log.warning(
                "mensaje invalido",
                extra={"context": {"messageId": message_id, "motivo": str(exc)}},
            )
            fallidos.append({"itemIdentifier": message_id})
        except Exception:
            log.exception(
                "fallo inesperado al procesar el mensaje",
                extra={"context": {"messageId": message_id}},
            )
            fallidos.append({"itemIdentifier": message_id})
        else:
            log.info(
                "pedido procesado",
                extra={
                    "context": {
                        "messageId": message_id,
                        "orderId": detail["orderId"],
                        "resultado": resultado,
                    }
                },
            )

    # ReportBatchItemFailures: solo los identificadores devueltos vuelven a la cola. Sin
    # esto, un unico mensaje malo obliga a reprocesar el lote entero.
    return {"batchItemFailures": fallidos}
