# Bus propio en lugar del bus default: el default lo comparte toda la cuenta y recibe
# ademas los eventos de los servicios de AWS, de modo que una regla mal escrita ahi
# afecta a terceros. Un bus dedicado se puede borrar entero sin consecuencias.
resource "aws_cloudwatch_event_bus" "orders" {
  name = "${local.name_prefix}-bus"
}

resource "aws_cloudwatch_event_rule" "order_placed" {
  name           = "${local.name_prefix}-order-placed"
  description    = "Deriva a la cola de proceso unicamente los eventos de pedido creado."
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

  # Seis veces el timeout de la funcion, que es la relacion que recomienda AWS para dar
  # margen a los reintentos del event source mapping. Si fuera menor, un mensaje todavia
  # en proceso volveria a hacerse visible y una segunda invocacion lo tomaria en paralelo.
  visibility_timeout_seconds = var.lambda_timeout_seconds * 6

  # Cuatro dias. Cubre un fin de semana largo con la funcion caida sin perder eventos.
  message_retention_seconds = 345600

  sqs_managed_sse_enabled = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    # Tres entregas fallidas y el mensaje sale de la cola. Sin esto, un unico mensaje
    # envenenado se reintenta para siempre y frena al resto de la particion.
    maxReceiveCount = 3
  })
}

resource "aws_sqs_queue" "dlq" {
  name = "${local.name_prefix}-dlq"

  # Catorce dias, el maximo. Lo que cae aca se inspecciona a mano y esa ventana tiene que
  # aguantar vacaciones de quien esta de guardia.
  message_retention_seconds = 1209600

  sqs_managed_sse_enabled = true
}

# EventBridge entrega a la cola con su propia identidad de servicio, no con un rol.
# La condicion sobre SourceArn evita el problema del confused deputy: sin ella,
# cualquier regla de cualquier cuenta podria escribir en esta cola.
data "aws_iam_policy_document" "process_queue" {
  statement {
    sid    = "PermiteEnvioDesdeLaReglaDeEventBridge"
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

  # LocalStack community no expone las claves administradas por AWS, asi que el cifrado
  # con KMS solo se pide contra la nube real. El contenido de estas alertas es el nombre
  # de una cola y un contador, no datos de cliente.
  kms_master_key_id = var.use_localstack ? null : "alias/aws/sns"
}

# La confirmacion de una suscripcion por email es manual: AWS manda un correo y la
# suscripcion queda en estado pending hasta que alguien lo abre. Por eso el default es
# vacio y no se crea nada si nadie declaro un destinatario.
resource "aws_sns_topic_subscription" "alerts_email" {
  count = var.alert_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}
