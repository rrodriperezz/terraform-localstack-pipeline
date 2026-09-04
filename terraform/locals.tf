locals {
  name_prefix = "${var.project_name}-${var.environment}"

  function_name = "${local.name_prefix}-processor"

  # El nombre del log group de una funcion no es configurable: Lambda escribe siempre en
  # /aws/lambda/<nombre>. Se declara aca porque lo necesitan tanto la politica del rol
  # como el recurso del log group, y son archivos distintos.
  log_group_name = "/aws/lambda/${local.function_name}"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
