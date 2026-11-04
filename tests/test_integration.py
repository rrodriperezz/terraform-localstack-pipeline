import json
import time
from uuid import uuid4

from boto3.dynamodb.conditions import Key

# Margin to prove that something does NOT happen. Waiting for an item to appear allows
# retries; proving that a second item never appears requires a fixed window held open.
QUIET_WINDOW = 20


def publish(events, outputs, detail, detail_type="order.placed"):
    response = events.put_events(
        Entries=[
            {
                "EventBusName": outputs["event_bus_name"],
                "Source": "orders.api",
                "DetailType": detail_type,
                "Detail": json.dumps(detail),
            }
        ]
    )

    assert response["FailedEntryCount"] == 0

    return response


def order(**overrides):
    base = {
        "orderId": f"ord-{uuid4().hex[:10]}",
        "createdAt": "2026-03-01T09:30:00+00:00",
        "customerId": f"cus-{uuid4().hex[:6]}",
        "amount": 320.75,
    }
    base.update(overrides)

    return base


def visible_messages(sqs, url):
    attributes = sqs.get_queue_attributes(
        QueueUrl=url,
        AttributeNames=[
            "ApproximateNumberOfMessages",
            "ApproximateNumberOfMessagesNotVisible",
        ],
    )["Attributes"]

    return int(attributes["ApproximateNumberOfMessages"]) + int(
        attributes["ApproximateNumberOfMessagesNotVisible"]
    )


def test_happy_path(events, dynamodb, outputs, wait_until):
    event = order()
    publish(events, outputs, event)

    table = dynamodb.Table(outputs["table_name"])

    item = wait_until(
        lambda: table.get_item(
            Key={"orderId": event["orderId"], "createdAt": event["createdAt"]}
        ).get("Item"),
        timeout=180,
        description="the order to appear in dynamodb",
    )

    assert item["customerId"] == event["customerId"]
    assert float(item["amount"]) == event["amount"]
    assert int(item["expiresAt"]) > time.time()


def test_redelivery_does_not_duplicate_the_order(events, dynamodb, outputs, wait_until):
    event = order()
    table = dynamodb.Table(outputs["table_name"])

    def order_items():
        return table.query(KeyConditionExpression=Key("orderId").eq(event["orderId"]))["Items"]

    publish(events, outputs, event)
    publish(events, outputs, event)

    wait_until(order_items, timeout=180, description="the order to be written")

    # The second write may arrive after the first read, so the full window is allowed to
    # pass before counting.
    time.sleep(QUIET_WINDOW)

    assert len(order_items()) == 1


def test_negative_amount_ends_up_in_the_dlq(events, sqs, outputs, wait_until):
    publish(events, outputs, order(amount=-42.0))

    # Generous timeout: there are three deliveries, and between each one the message stays
    # invisible for the queue's full visibility timeout.
    wait_until(
        lambda: visible_messages(sqs, outputs["dlq_url"]) >= 1,
        timeout=300,
        interval=5,
        description="the poison message to land in the dlq",
    )


def test_rule_drops_other_event_types(events, sqs, outputs):
    sqs.purge_queue(QueueUrl=outputs["queue_url"])
    time.sleep(QUIET_WINDOW)

    publish(events, outputs, order(), detail_type="order.cancelled")
    time.sleep(QUIET_WINDOW)

    assert visible_messages(sqs, outputs["queue_url"]) == 0
