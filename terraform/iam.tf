data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    sid     = "AllowLambdaToAssumeRole"
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

# One role per function and one concrete resource per statement. Neither
# AWSLambdaBasicExecutionRole nor any wildcard in resources is used: that managed policy
# allows logging to every log group in the account, which is strictly more than this
# function needs.
data "aws_iam_policy_document" "processor" {
  statement {
    sid    = "WriteOwnLogs"
    effect = "Allow"

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    # The :* suffix covers the log streams inside the group, which are the actual
    # PutLogEvents resource. Without it, the function cannot write a single line.
    resources = [
      "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:${local.log_group_name}:*",
    ]
  }

  statement {
    sid    = "ConsumeProcessQueue"
    effect = "Allow"

    # All three are called by the event source mapping on the function's behalf, not by
    # the handler code. Without DeleteMessage the message would be redelivered until it
    # landed in the DLQ.
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
    ]

    resources = [aws_sqs_queue.process.arn]
  }

  statement {
    sid    = "ReadWriteOrdersTable"
    effect = "Allow"

    actions = [
      "dynamodb:PutItem",
      "dynamodb:GetItem",
    ]

    resources = [aws_dynamodb_table.orders.arn]
  }

  statement {
    sid       = "PublishToAlertsTopic"
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
