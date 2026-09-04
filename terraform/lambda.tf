data "archive_file" "processor" {
  type        = "zip"
  source_dir  = "${path.module}/../src/processor"
  output_path = "${path.module}/.build/processor.zip"

  # requirements.txt esta vacio y solo documenta que no hay dependencias; los .pyc son
  # de la maquina que empaqueto. Incluirlos cambia el hash del zip en cada equipo y
  # provoca un redespliegue de la funcion sin que el codigo haya cambiado.
  excludes = [
    "requirements.txt",
    "__pycache__",
  ]
}

# Declarado de forma explicita y no delegado a Lambda. Si lo crea el servicio en el
# primer invoke, nace con retencion infinita, queda fuera del estado de Terraform y el
# destroy lo deja huerfano acumulando costo de almacenamiento para siempre.
resource "aws_cloudwatch_log_group" "processor" {
  name              = local.log_group_name
  retention_in_days = var.log_retention_days
}

resource "aws_lambda_function" "processor" {
  function_name = local.function_name
  role          = aws_iam_role.processor.arn

  runtime = "python3.12"
  handler = "handler.handler"

  filename = data.archive_file.processor.output_path

  # Es lo que le dice a Lambda que el contenido cambio. Sin esto Terraform compara solo
  # el nombre del archivo y nunca vuelve a subir el codigo.
  source_code_hash = data.archive_file.processor.output_base64sha256

  memory_size = var.lambda_memory_mb
  timeout     = var.lambda_timeout_seconds

  environment {
    variables = {
      TABLE_NAME   = aws_dynamodb_table.orders.name
      ALERTS_TOPIC = aws_sns_topic.alerts.arn
      LOG_LEVEL    = var.environment == "prod" ? "INFO" : "DEBUG"
    }
  }

  # La politica y el log group no son dependencias implicitas de la funcion, pero si lo
  # son en la practica: si la funcion arranca antes de que existan, el primer invoke
  # falla por permisos y crea el log group por su cuenta con retencion infinita.
  depends_on = [
    aws_iam_role_policy.processor,
    aws_cloudwatch_log_group.processor,
  ]
}

resource "aws_lambda_event_source_mapping" "process_queue" {
  event_source_arn = aws_sqs_queue.process.arn
  function_name    = aws_lambda_function.processor.arn

  # Diez mensajes por invocacion. Junto con ReportBatchItemFailures, un mensaje malo
  # dentro del lote vuelve solo a la cola y los otros nueve se dan por procesados.
  batch_size                         = 10
  function_response_types            = ["ReportBatchItemFailures"]
  maximum_batching_window_in_seconds = 5
}
