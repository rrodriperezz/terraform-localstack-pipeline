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
  #checkov:skip=CKV_AWS_158:Los logs nunca incluyen datos de cliente, y una CMK para cifrarlos agrega costo fijo sin reducir ningun riesgo real.
  #checkov:skip=CKV_AWS_338:Catorce dias es deliberado y sale de una variable. Guardar doce meses de logs de un pipeline de eventos es gasto puro.
  name              = local.log_group_name
  retention_in_days = var.log_retention_days
}

resource "aws_lambda_function" "processor" {
  #checkov:skip=CKV_AWS_116:El destino de fallo es la DLQ de SQS. La DLQ a nivel de funcion solo aplica a invocaciones asincronicas, y esta se invoca desde un event source mapping.
  #checkov:skip=CKV_AWS_117:La funcion solo habla con APIs de AWS. Meterla en una VPC exigiria NAT o endpoints de interfaz, que cuestan mas que todo el resto del pipeline junto.
  #checkov:skip=CKV_AWS_173:Las variables de entorno son un nombre de tabla y un ARN, ambos publicos dentro de la cuenta. No hay secretos que cifrar.
  #checkov:skip=CKV_AWS_272:La firma de codigo necesita un perfil de AWS Signer y una cadena de build reproducible. Queda fuera del alcance declarado.
  #checkov:skip=CKV_AWS_50:El pipeline tiene un solo salto y la observabilidad va por logs JSON y alarmas. X-Ray agregaria costo por traza sin responder ninguna pregunta que hoy no se pueda responder.
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

  # Techo de concurrencia en prod: acota cuantas escrituras simultaneas puede recibir
  # DynamoDB y evita que un pico de eventos se lleve toda la concurrencia de la cuenta.
  # En local queda sin reservar, porque reservar cupo con un solo consumidor no aporta.
  reserved_concurrent_executions = var.environment == "prod" ? 20 : -1

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
