import json
import logging
import os
import time
from datetime import UTC, datetime
from decimal import Decimal

import boto3
from botocore.exceptions import ClientError

RETENTION_DAYS = 90
SECONDS_PER_DAY = 86400


class ValidationError(Exception):
    """A message no retry will ever fix: it is dropped toward the DLQ."""


class JsonFormatter(logging.Formatter):
    def format(self, record):
        payload = {
            "level": record.levelname,
            "message": record.getMessage(),
        }

        context = getattr(record, "context", None)
        if context is not None:
            payload["context"] = context

        if record.exc_info:
            payload["error"] = self.formatException(record.exc_info)

        return json.dumps(payload, ensure_ascii=False)


def _build_logger():
    logger = logging.getLogger("processor")
    logger.setLevel(os.environ.get("LOG_LEVEL", "INFO").upper())

    # The Lambda runtime installs its own plain-text handler on the root logger.
    # Without propagate set to False every line is emitted twice, once as JSON and once not.
    output = logging.StreamHandler()
    output.setFormatter(JsonFormatter())
    logger.handlers = [output]
    logger.propagate = False

    return logger


log = _build_logger()

_table = None


def get_table():
    # Lazy and cached: the resource survives between invocations of the same container,
    # so building it costs once per cold start instead of once per message. Building it
    # at import time would require valid credentials just to import the file in unit tests.
    global _table

    if _table is None:
        _table = boto3.resource("dynamodb").Table(os.environ["TABLE_NAME"])

    return _table


def parse_record(record):
    try:
        body = json.loads(record["body"])
    except (KeyError, TypeError, ValueError) as exc:
        raise ValidationError("the message body is not valid JSON") from exc

    detail = body.get("detail")

    if not isinstance(detail, dict):
        raise ValidationError("the event has no object-typed detail")

    return detail


def validate(detail):
    for field in ("orderId", "customerId"):
        value = detail.get(field)

        if not isinstance(value, str) or not value.strip():
            raise ValidationError(f"missing required field {field}")

    try:
        amount = float(detail["amount"])
    except (KeyError, TypeError, ValueError) as exc:
        raise ValidationError("amount is not a number") from exc

    # A negative amount is not a transient error, but it is not something to ignore
    # silently either: it is the case that pushes the message into the DLQ and fires the
    # alarm so someone looks at where it came from.
    if amount < 0:
        raise ValidationError("negative amount")

    return amount


def store(detail, amount):
    now = int(time.time())

    item = {
        "orderId": detail["orderId"],
        # createdAt is part of the key. If the producer does not send it, every redelivery
        # generates a different key and the conditional write is no longer idempotent.
        "createdAt": detail.get("createdAt") or datetime.fromtimestamp(now, UTC).isoformat(),
        "customerId": detail["customerId"],
        # DynamoDB does not accept float: it loses precision when serializing. A Decimal
        # built from the string representation keeps exactly what arrived in the event.
        "amount": Decimal(str(amount)),
        "expiresAt": now + RETENTION_DAYS * SECONDS_PER_DAY,
    }

    try:
        get_table().put_item(
            Item=item,
            # SQS delivers at least once. Without this condition, a retry of the same
            # message would overwrite the original item and count the order twice.
            ConditionExpression="attribute_not_exists(orderId)",
        )
    except ClientError as exc:
        if exc.response["Error"]["Code"] == "ConditionalCheckFailedException":
            return "duplicate"
        raise

    return "created"


def handler(event, context):
    failures = []

    for record in event.get("Records", []):
        message_id = record.get("messageId")

        try:
            detail = parse_record(record)
            amount = validate(detail)
            result = store(detail, amount)
        except ValidationError as exc:
            # Log the reason and the identifier, never the full event: the detail carries
            # customer data and logs are retained and shared.
            log.warning(
                "invalid message",
                extra={"context": {"messageId": message_id, "reason": str(exc)}},
            )
            failures.append({"itemIdentifier": message_id})
        except Exception:
            log.exception(
                "unexpected failure while processing the message",
                extra={"context": {"messageId": message_id}},
            )
            failures.append({"itemIdentifier": message_id})
        else:
            log.info(
                "order processed",
                extra={
                    "context": {
                        "messageId": message_id,
                        "orderId": detail["orderId"],
                        "result": result,
                    }
                },
            )

    # ReportBatchItemFailures: only the returned identifiers go back to the queue. Without
    # this, a single bad message forces the whole batch to be reprocessed.
    return {"batchItemFailures": failures}
