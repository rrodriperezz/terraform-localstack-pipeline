# The integration tests read these values with terraform output -json instead of
# rebuilding the names by hand. That way a prefix change does not break the tests.
output "event_bus_name" {
  description = "EventBridge bus where order events are published."
  value       = aws_cloudwatch_event_bus.orders.name
}

output "queue_url" {
  description = "URL of the main processing queue."
  value       = aws_sqs_queue.process.url
}

output "dlq_url" {
  description = "URL of the dead-letter queue."
  value       = aws_sqs_queue.dlq.url
}

output "table_name" {
  description = "DynamoDB table where the handler writes orders."
  value       = aws_dynamodb_table.orders.name
}

output "function_name" {
  description = "Name of the processor function."
  value       = aws_lambda_function.processor.function_name
}

output "alerts_topic_arn" {
  description = "SNS topic the alarms point to."
  value       = aws_sns_topic.alerts.arn
}
