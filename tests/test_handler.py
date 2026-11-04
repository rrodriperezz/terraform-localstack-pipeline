import json
from unittest.mock import MagicMock, patch

import pytest
from botocore.exceptions import ClientError

import handler


def sqs_record(detail, message_id="msg-1", detail_type="order.placed", body=None):
    if body is None:
        body = json.dumps({"detail-type": detail_type, "detail": detail})

    return {"messageId": message_id, "body": body}


def order(**overrides):
    base = {
        "orderId": "ord-001",
        "createdAt": "2026-01-15T10:00:00+00:00",
        "customerId": "cus-77",
        "amount": 149.9,
    }
    base.update(overrides)

    return base


@pytest.fixture
def table():
    fake = MagicMock()

    with patch.object(handler, "get_table", return_value=fake):
        yield fake


def test_valid_event_writes_once(table):
    result = handler.handler({"Records": [sqs_record(order())]}, None)

    assert result == {"batchItemFailures": []}
    assert table.put_item.call_count == 1

    kwargs = table.put_item.call_args.kwargs
    assert kwargs["Item"]["orderId"] == "ord-001"
    assert kwargs["ConditionExpression"] == "attribute_not_exists(orderId)"


def test_missing_customer_id(table):
    detail = order()
    del detail["customerId"]

    result = handler.handler({"Records": [sqs_record(detail, "msg-no-customer")]}, None)

    assert result == {"batchItemFailures": [{"itemIdentifier": "msg-no-customer"}]}
    table.put_item.assert_not_called()


def test_negative_amount(table):
    result = handler.handler(
        {"Records": [sqs_record(order(amount=-1), "msg-negative")]},
        None,
    )

    assert result == {"batchItemFailures": [{"itemIdentifier": "msg-negative"}]}
    table.put_item.assert_not_called()


def test_non_numeric_amount(table):
    result = handler.handler(
        {"Records": [sqs_record(order(amount="one hundred forty"), "msg-text")]},
        None,
    )

    assert result == {"batchItemFailures": [{"itemIdentifier": "msg-text"}]}
    table.put_item.assert_not_called()


def test_body_that_is_not_json(table):
    record = sqs_record(None, "msg-broken", body="this is not json")

    result = handler.handler({"Records": [record]}, None)

    assert result == {"batchItemFailures": [{"itemIdentifier": "msg-broken"}]}
    table.put_item.assert_not_called()


def test_duplicate_is_not_a_failure(table):
    table.put_item.side_effect = ClientError(
        {"Error": {"Code": "ConditionalCheckFailedException", "Message": "already exists"}},
        "PutItem",
    )

    result = handler.handler({"Records": [sqs_record(order(), "msg-repeated")]}, None)

    # The condition fails because the item was already there: reprocessing is correct and
    # the message counts as consumed. Reporting it as a failure would send it to the DLQ
    # for no reason.
    assert result == {"batchItemFailures": []}


def test_batch_with_one_failure_in_the_middle(table):
    records = [
        sqs_record(order(orderId="ord-001"), "msg-a"),
        sqs_record(order(orderId="ord-002", amount=-5), "msg-b"),
        sqs_record(order(orderId="ord-003"), "msg-c"),
    ]

    result = handler.handler({"Records": records}, None)

    assert result == {"batchItemFailures": [{"itemIdentifier": "msg-b"}]}
    assert table.put_item.call_count == 2

    written = [call.kwargs["Item"]["orderId"] for call in table.put_item.call_args_list]
    assert written == ["ord-001", "ord-003"]
