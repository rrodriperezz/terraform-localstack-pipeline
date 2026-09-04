data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    sid     = "PermiteAsumirRolALambda"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "processor" {
  name               = "${local.function_name}-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

# Un rol por funcion y un recurso concreto por statement. No se usa
# AWSLambdaBasicExecutionRole ni ningun comodin en resources: esa politica administrada
# habilita logs sobre todos los log groups de la cuenta, que es estricamente mas de lo
# que esta funcion necesita.
data "aws_iam_policy_document" "processor" {
  statement {
    sid    = "EscribeSusPropiosLogs"
    effect = "Allow"

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    # El sufijo :* alcanza a los log streams dentro del grupo, que son el recurso real de
    # PutLogEvents. Sin el, la funcion no puede escribir ni una linea.
    resources = [
      "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:${local.log_group_name}:*",
    ]
  }

  statement {
    sid    = "ConsumeLaColaDeProceso"
    effect = "Allow"

    # Las tres las ejecuta el event source mapping en nombre de la funcion, no el codigo
    # del handler. Sin DeleteMessage el mensaje volveria a entregarse hasta caer en la DLQ.
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
    ]

    resources = [aws_sqs_queue.process.arn]
  }

  statement {
    sid    = "EscribeYLeeLaTablaDePedidos"
    effect = "Allow"

    actions = [
      "dynamodb:PutItem",
      "dynamodb:GetItem",
    ]

    resources = [aws_dynamodb_table.orders.arn]
  }

  statement {
    sid       = "PublicaEnElTopicoDeAlertas"
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]
  }
}

resource "aws_iam_role_policy" "processor" {
  name   = "${local.function_name}-policy"
  role   = aws_iam_role.processor.id
  policy = data.aws_iam_policy_document.processor.json
}
