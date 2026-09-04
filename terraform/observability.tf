# La alarma va sobre la profundiad de la DLQ y no sobre los errores de la funcion. Un
# error aislado que el reintento resuelve no es un incidente y despertar a alguien por
# eso entrena al equipo a ignorar las alarmas. Un mensaje en la DLQ si lo es: significa
# que los tres reintentos ya se agotaron y ese pedido no se proceso.
resource "aws_cloudwatch_metric_alarm" "dlq_con_mensajes" {
  alarm_name        = "${local.name_prefix}-dlq-con-mensajes"
  alarm_description = "Hay mensajes en la DLQ: se agotaron los reintentos de al menos un pedido."

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

  # SQS no publica la metrica cuando la cola esta vacia. Con el default, la alarma se
  # quedaria en INSUFFICIENT_DATA justo en el estado sano, que es el mas frecuente.
  treat_missing_data = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

# Complementaria y deliberadamente menos sensible: cinco errores en cinco minutos,
# sostenidos durante dos ventanas. Detecta que algo esta roto de forma sistematica
# antes de que la DLQ se llene, sin disparar por un throttling puntual.
resource "aws_cloudwatch_metric_alarm" "errores_de_la_funcion" {
  alarm_name        = "${local.name_prefix}-errores-lambda"
  alarm_description = "La funcion procesadora acumula errores durante dos ventanas seguidas."

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
