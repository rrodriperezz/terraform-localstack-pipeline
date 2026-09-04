import json
from unittest.mock import MagicMock, patch

import pytest
from botocore.exceptions import ClientError

import handler


def sqs_record(detail, message_id="msg-1", detail_type="order.placed", body=None):
    if body is None:
        body = json.dumps({"detail-type": detail_type, "detail": detail})

    return {"messageId": message_id, "body": body}


def pedido(**overrides):
    base = {
        "orderId": "ord-001",
        "createdAt": "2026-01-15T10:00:00+00:00",
        "customerId": "cus-77",
        "amount": 149.9,
    }
    base.update(overrides)

    return base


@pytest.fixture
def tabla():
    doble = MagicMock()

    with patch.object(handler, "get_table", return_value=doble):
        yield doble


def test_evento_valido_escribe_una_vez(tabla):
    resultado = handler.handler({"Records": [sqs_record(pedido())]}, None)

    assert resultado == {"batchItemFailures": []}
    assert tabla.put_item.call_count == 1

    argumentos = tabla.put_item.call_args.kwargs
    assert argumentos["Item"]["orderId"] == "ord-001"
    assert argumentos["ConditionExpression"] == "attribute_not_exists(orderId)"


def test_falta_customer_id(tabla):
    detail = pedido()
    del detail["customerId"]

    resultado = handler.handler({"Records": [sqs_record(detail, "msg-sin-cliente")]}, None)

    assert resultado == {"batchItemFailures": [{"itemIdentifier": "msg-sin-cliente"}]}
    tabla.put_item.assert_not_called()


def test_importe_negativo(tabla):
    resultado = handler.handler(
        {"Records": [sqs_record(pedido(amount=-1), "msg-negativo")]},
        None,
    )

    assert resultado == {"batchItemFailures": [{"itemIdentifier": "msg-negativo"}]}
    tabla.put_item.assert_not_called()


def test_importe_no_numerico(tabla):
    resultado = handler.handler(
        {"Records": [sqs_record(pedido(amount="ciento cuarenta"), "msg-texto")]},
        None,
    )

    assert resultado == {"batchItemFailures": [{"itemIdentifier": "msg-texto"}]}
    tabla.put_item.assert_not_called()


def test_cuerpo_que_no_es_json(tabla):
    record = sqs_record(None, "msg-roto", body="esto no es json")

    resultado = handler.handler({"Records": [record]}, None)

    assert resultado == {"batchItemFailures": [{"itemIdentifier": "msg-roto"}]}
    tabla.put_item.assert_not_called()


def test_duplicado_no_es_fallo(tabla):
    tabla.put_item.side_effect = ClientError(
        {"Error": {"Code": "ConditionalCheckFailedException", "Message": "ya existe"}},
        "PutItem",
    )

    resultado = handler.handler({"Records": [sqs_record(pedido(), "msg-repetido")]}, None)

    # La condicion falla porque el item ya estaba: el reprocesamento es correcto y el
    # mensaje se da por consumido. Devolverlo como fallo lo mandaria a la DLQ sin motivo.
    assert resultado == {"batchItemFailures": []}


def test_lote_con_un_fallo_en_el_medio(tabla):
    records = [
        sqs_record(pedido(orderId="ord-001"), "msg-a"),
        sqs_record(pedido(orderId="ord-002", amount=-5), "msg-b"),
        sqs_record(pedido(orderId="ord-003"), "msg-c"),
    ]

    resultado = handler.handler({"Records": records}, None)

    assert resultado == {"batchItemFailures": [{"itemIdentifier": "msg-b"}]}
    assert tabla.put_item.call_count == 2

    escritos = [llamada.kwargs["Item"]["orderId"] for llamada in tabla.put_item.call_args_list]
    assert escritos == ["ord-001", "ord-003"]
