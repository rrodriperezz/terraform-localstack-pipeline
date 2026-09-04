import json
import time
from uuid import uuid4

from boto3.dynamodb.conditions import Key

# Margen para demostrar que algo NO pasa. Esperar a que aparezca un item admite reintentos;
# comprobar que no aparece un segundo item obliga a fijar una ventana y aguantarla.
VENTANA_DE_REPOSO = 20


def publicar(eventos, outputs, detail, detail_type="order.placed"):
    respuesta = eventos.put_events(
        Entries=[
            {
                "EventBusName": outputs["event_bus_name"],
                "Source": "orders.api",
                "DetailType": detail_type,
                "Detail": json.dumps(detail),
            }
        ]
    )

    assert respuesta["FailedEntryCount"] == 0

    return respuesta


def pedido(**overrides):
    base = {
        "orderId": f"ord-{uuid4().hex[:10]}",
        "createdAt": "2026-03-01T09:30:00+00:00",
        "customerId": f"cus-{uuid4().hex[:6]}",
        "amount": 320.75,
    }
    base.update(overrides)

    return base


def mensajes_visibles(sqs, url):
    atributos = sqs.get_queue_attributes(
        QueueUrl=url,
        AttributeNames=[
            "ApproximateNumberOfMessages",
            "ApproximateNumberOfMessagesNotVisible",
        ],
    )["Attributes"]

    return int(atributos["ApproximateNumberOfMessages"]) + int(
        atributos["ApproximateNumberOfMessagesNotVisible"]
    )


def test_camino_feliz(eventos, dynamodb, outputs, wait_until):
    evento = pedido()
    publicar(eventos, outputs, evento)

    tabla = dynamodb.Table(outputs["table_name"])

    item = wait_until(
        lambda: tabla.get_item(
            Key={"orderId": evento["orderId"], "createdAt": evento["createdAt"]}
        ).get("Item"),
        timeout=180,
        descripcion="que el pedido aparezca en dynamodb",
    )

    assert item["customerId"] == evento["customerId"]
    assert float(item["amount"]) == evento["amount"]
    assert int(item["expiresAt"]) > time.time()


def test_reentrega_no_duplica_el_pedido(eventos, dynamodb, outputs, wait_until):
    evento = pedido()
    tabla = dynamodb.Table(outputs["table_name"])

    def items_del_pedido():
        return tabla.query(KeyConditionExpression=Key("orderId").eq(evento["orderId"]))["Items"]

    publicar(eventos, outputs, evento)
    publicar(eventos, outputs, evento)

    wait_until(items_del_pedido, timeout=180, descripcion="que el pedido se escriba")

    # La segunda escritura pudo llegar despues de la primera lectura, asi que se deja
    # pasar la ventana completa antes de contar.
    time.sleep(VENTANA_DE_REPOSO)

    assert len(items_del_pedido()) == 1


def test_importe_negativo_termina_en_la_dlq(eventos, sqs, outputs, wait_until):
    publicar(eventos, outputs, pedido(amount=-42.0))

    # Timeout generoso: son tres entregas, y entre una y otra el mensaje queda invisible
    # durante el visibility timeout completo de la cola.
    wait_until(
        lambda: mensajes_visibles(sqs, outputs["dlq_url"]) >= 1,
        timeout=300,
        intervalo=5,
        descripcion="que el mensaje envenenado caiga en la dlq",
    )


def test_la_regla_descarta_otros_tipos_de_evento(eventos, sqs, outputs):
    sqs.purge_queue(QueueUrl=outputs["queue_url"])
    time.sleep(VENTANA_DE_REPOSO)

    publicar(eventos, outputs, pedido(), detail_type="order.cancelled")
    time.sleep(VENTANA_DE_REPOSO)

    assert mensajes_visibles(sqs, outputs["queue_url"]) == 0
