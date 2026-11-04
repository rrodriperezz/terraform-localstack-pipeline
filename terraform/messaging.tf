# A dedicated bus instead of the default one: the default bus is shared by the whole
# account and also receives AWS service events, so a badly written rule there affects
# others. A dedicated bus can be deleted entirely with no side effects.
resource "aws_cloudwatch_event_bus" "orders" {
  name = "${local.name_prefix}-bus"
}

resource "aws_cloudwatch_event_rule" "order_placed" {
  name           = "${local.name_prefix}-order-placed"
  description    = "Routes only order-placed events to the processing queue."
  event_bus_name = aws_cloudwatch_event_bus.orders.name

  event_pattern = jsonencode({
    detail-type = ["order.placed"]
  })
}

resource "aws_cloudwatch_event_target" "to_queue" {
  rule           = aws_cloudwatch_event_rule.order_placed.name
  event_bus_name = aws_cloudwatch_event_bus.orders.name
  target_id      = "${local.name_prefix}-process-queue"
  arn            = aws_sqs_queue.process.arn
}

resource "aws_sqs_queue" "process" {
  name = "${local.name_prefix}-process"

  # Six times the function timeout, the ratio AWS recommends to leave room for the event
  # source mapping's retries. If it were lower, a message still being processed would
  # become visible again and a second invocation would pick it up in parallel.
  visibility_timeout_seconds = var.lambda_timeout_seconds * 6

  # Four days. Covers a long weekend with the function down without losing events.
  message_retention_seconds = 345600

  sqs_managed_sse_enabled = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    # Three failed deliveries and the message leaves the queue. Without this, a single
    # poison message is retried forever and holds up the rest of the partition.
    maxReceiveCount = 3
  })
}

resource "aws_sqs_queue" "dlq" {
  name = "${local.name_prefix}-dlq"

  # Fourteen days, the maximum. Whatever lands here is inspected by hand, and that window
  # has to survive the on-call person's vacation.
  message_retention_seconds = 1209600

  sqs_managed_sse_enabled = true
}

# EventBridge delivers to the queue with its own service identity, not with a role.
# The SourceArn condition prevents the confused deputy problem: without it, any rule in
# any account could write to this queue.
data "aws_iam_policy_document" "process_queue" {
  statement {
    sid    = "AllowSendFromEventBridgeRule"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.process.arn]

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_cloudwatch_event_rule.order_placed.arn]
    }
  }
}

resource "aws_sqs_queue_policy" "process" {
  queue_url = aws_sqs_queue.process.id
  policy    = data.aws_iam_policy_document.process_queue.json
}

resource "aws_sns_topic" "alerts" {
  name = "${local.name_prefix}-alerts"

  # LocalStack community does not expose AWS managed keys, so KMS encryption is only
  # requested against the real cloud. These alerts contain a queue name and a counter,
  # not customer data.
  kms_master_key_id = var.use_localstack ? null : "alias/aws/sns"
}

# Confirming an email subscription is manual: AWS sends an email and the subscription
# stays pending until someone opens it. That is why the default is empty and nothing is
# created unless a recipient is declared.
resource "aws_sns_topic_subscription" "alerts_email" {
  count = var.alert_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}
