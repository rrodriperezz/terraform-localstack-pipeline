data "archive_file" "processor" {
  type        = "zip"
  source_dir  = "${path.module}/../src/processor"
  output_path = "${path.module}/.build/processor.zip"

  # requirements.txt is empty and only documents that there are no dependencies; the .pyc
  # files belong to whichever machine did the packaging. Including them changes the zip
  # hash on every machine and triggers a function redeploy with no code change.
  excludes = [
    "requirements.txt",
    "__pycache__",
  ]
}

# Declared explicitly instead of leaving it to Lambda. If the service creates it on the
# first invoke, it starts with infinite retention, lives outside the Terraform state and
# destroy leaves it orphaned, accumulating storage cost forever.
resource "aws_cloudwatch_log_group" "processor" {
  #checkov:skip=CKV_AWS_158:Logs never include customer data, and a CMK to encrypt them adds fixed cost without reducing any real risk.
  #checkov:skip=CKV_AWS_338:Fourteen days is deliberate and comes from a variable. Keeping twelve months of logs for an event pipeline is pure cost.
  name              = local.log_group_name
  retention_in_days = var.log_retention_days
}

resource "aws_lambda_function" "processor" {
  #checkov:skip=CKV_AWS_116:The failure destination is the SQS DLQ. A function-level DLQ only applies to asynchronous invocations, and this one is invoked from an event source mapping.
  #checkov:skip=CKV_AWS_117:The function only talks to AWS APIs. Putting it in a VPC would require NAT or interface endpoints, which cost more than the rest of the pipeline combined.
  #checkov:skip=CKV_AWS_173:The environment variables are a table name and an ARN, both public within the account. There are no secrets to encrypt.
  #checkov:skip=CKV_AWS_272:Code signing needs an AWS Signer profile and a reproducible build chain. It is outside the declared scope.
  #checkov:skip=CKV_AWS_50:The pipeline has a single hop and observability goes through JSON logs and alarms. X-Ray would add per-trace cost without answering any question that cannot be answered today.
  function_name = local.function_name
  role          = aws_iam_role.processor.arn

  runtime = "python3.12"
  handler = "handler.handler"

  filename = data.archive_file.processor.output_path

  # This is what tells Lambda the content changed. Without it Terraform only compares
  # the file name and never uploads the code again.
  source_code_hash = data.archive_file.processor.output_base64sha256

  memory_size = var.lambda_memory_mb
  timeout     = var.lambda_timeout_seconds

  # Concurrency ceiling in prod: it bounds how many concurrent writes DynamoDB can receive
  # and keeps an event spike from taking all of the account's concurrency.
  # Locally it stays unreserved, because reserving capacity with a single consumer adds nothing.
  reserved_concurrent_executions = var.environment == "prod" ? 20 : -1

  environment {
    variables = {
      TABLE_NAME   = aws_dynamodb_table.orders.name
      ALERTS_TOPIC = aws_sns_topic.alerts.arn
      LOG_LEVEL    = var.environment == "prod" ? "INFO" : "DEBUG"
    }
  }

  # The policy and the log group are not implicit dependencies of the function, but they
  # are in practice: if the function starts before they exist, the first invoke fails on
  # permissions and creates the log group itself with infinite retention.
  depends_on = [
    aws_iam_role_policy.processor,
    aws_cloudwatch_log_group.processor,
  ]
}

resource "aws_lambda_event_source_mapping" "process_queue" {
  event_source_arn = aws_sqs_queue.process.arn
  function_name    = aws_lambda_function.processor.arn

  # Ten messages per invocation. Together with ReportBatchItemFailures, a bad message
  # inside the batch is the only one that goes back to the queue; the other nine count as processed.
  batch_size                         = 10
  function_response_types            = ["ReportBatchItemFailures"]
  maximum_batching_window_in_seconds = 5
}
