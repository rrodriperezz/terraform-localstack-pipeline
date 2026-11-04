locals {
  name_prefix = "${var.project_name}-${var.environment}"

  function_name = "${local.name_prefix}-processor"

  # A function's log group name is not configurable: Lambda always writes to
  # /aws/lambda/<name>. It is declared here because both the role policy and the log
  # group resource need it, and they live in different files.
  log_group_name = "/aws/lambda/${local.function_name}"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
