provider "aws" {
  region = var.aws_region

  # LocalStack does not validate credentials, but the provider does require them to exist
  # and to look like an AWS key. Against the real cloud these stay null and credentials
  # come from the standard chain (profile, environment variables or role).
  access_key = var.use_localstack ? "test" : null
  secret_key = var.use_localstack ? "test" : null

  # The three calls these flags skip go to the metadata endpoint or to real STS.
  # Against LocalStack they hang until the timeout and slow down every plan.
  skip_credentials_validation = var.use_localstack
  skip_metadata_api_check     = var.use_localstack
  skip_requesting_account_id  = var.use_localstack

  # A dynamic block over an empty list emits nothing, so the same code works against
  # real AWS without splitting the provider into two definitions.
  dynamic "endpoints" {
    for_each = var.use_localstack ? [1] : []

    # events and logs are the canonical names. cloudwatchevents and cloudwatchlogs are
    # historical aliases for the same services: declaring both makes the provider warn
    # that the combination is invalid, and from version 6 on it will be an error.
    content {
      cloudwatch = var.localstack_endpoint
      dynamodb   = var.localstack_endpoint
      events     = var.localstack_endpoint
      iam        = var.localstack_endpoint
      lambda     = var.localstack_endpoint
      logs       = var.localstack_endpoint
      sns        = var.localstack_endpoint
      sqs        = var.localstack_endpoint
      sts        = var.localstack_endpoint
    }
  }

  default_tags {
    tags = local.common_tags
  }
}
