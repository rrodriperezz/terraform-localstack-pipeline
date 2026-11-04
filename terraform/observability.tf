# The alarm watches the DLQ depth, not the function's errors. An isolated error that a
# retry fixes is not an incident, and waking someone up for it trains the team to ignore
# alarms. A message in the DLQ is one: it means all three retries are exhausted and that
# order was not processed.
resource "aws_cloudwatch_metric_alarm" "dlq_has_messages" {
  alarm_name        = "${local.name_prefix}-dlq-has-messages"
  alarm_description = "There are messages in the DLQ: retries ran out for at least one order."

  namespace   = "AWS/SQS"
  metric_name = "ApproximateNumberOfMessagesVisible"

  dimensions = {
    QueueName = aws_sqs_queue.dlq.name
  }

  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  threshold           = var.dlq_alarm_threshold
  comparison_operator = "GreaterThanOrEqualToThreshold"

  # SQS does not publish the metric while the queue is empty. With the default, the alarm
  # would sit in INSUFFICIENT_DATA precisely in the healthy state, which is the most common one.
  treat_missing_data = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

# Complementary and deliberately less sensitive: five errors in five minutes, sustained
# over two windows. It catches something systematically broken before the DLQ fills up,
# without firing on a one-off throttle.
resource "aws_cloudwatch_metric_alarm" "function_errors" {
  alarm_name        = "${local.name_prefix}-lambda-errors"
  alarm_description = "The processor function keeps erroring over two consecutive windows."

  namespace   = "AWS/Lambda"
  metric_name = "Errors"

  dimensions = {
    FunctionName = aws_lambda_function.processor.function_name
  }

  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 2
  threshold           = 5
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}
