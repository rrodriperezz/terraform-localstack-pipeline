# Las pruebas de integracion leen estos valores con terraform output -json en vez de
# reconstruir los nombres a mano. Asi un cambio de prefijo no rompe los tests.
output "event_bus_name" {
  description = "Bus de EventBridge donde se publican los eventos de pedido."
  value       = aws_cloudwatch_event_bus.orders.name
}

output "queue_url" {
  description = "URL de la cola principal de proceso."
  value       = aws_sqs_queue.process.url
}

output "dlq_url" {
  description = "URL de la cola de mensajes muertos."
  value       = aws_sqs_queue.dlq.url
}

output "table_name" {
  description = "Tabla de DynamoDB donde el handler escribe los pedidos."
  value       = aws_dynamodb_table.orders.name
}

output "function_name" {
  description = "Nombre de la funcion procesadora."
  value       = aws_lambda_function.processor.function_name
}

output "alerts_topic_arn" {
  description = "Topico SNS al que apuntan las alarmas."
  value       = aws_sns_topic.alerts.arn
}
