variable "project_name" {
  description = "Prefix for every resource. Combined with environment it forms name_prefix."
  type        = string
  default     = "order-events"
}

variable "environment" {
  description = "Deployment environment. Sets the name suffix and whether PITR is enabled."
  type        = string

  validation {
    condition     = contains(["local", "prod"], var.environment)
    error_message = "The environment must be local or prod."
  }
}

variable "aws_region" {
  description = "AWS region. It does not matter against LocalStack, but it is part of every ARN."
  type        = string
  default     = "us-east-1"
}

variable "use_localstack" {
  description = "Points every provider endpoint at LocalStack and skips credential validation."
  type        = bool
  default     = false
}

variable "localstack_endpoint" {
  description = "URL of LocalStack's single gateway. Only used when use_localstack is true."
  type        = string
  default     = "http://localhost:4566"
}

variable "lambda_memory_mb" {
  description = "Memory for the processor function. In Lambda, CPU scales with memory."
  type        = number
  default     = 256

  validation {
    condition     = var.lambda_memory_mb >= 128 && var.lambda_memory_mb <= 3008
    error_message = "The function memory must be between 128 and 3008 MB."
  }
}

variable "lambda_timeout_seconds" {
  description = "Function timeout. The queue's visibility timeout is derived from this value."
  type        = number
  default     = 30

  validation {
    condition     = var.lambda_timeout_seconds >= 1 && var.lambda_timeout_seconds <= 900
    error_message = "The function timeout must be between 1 and 900 seconds."
  }
}

variable "log_retention_days" {
  description = "Retention, in days, for the function's log group."
  type        = number
  default     = 14

  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 3653
    error_message = "Log retention must be between 1 and 3653 days."
  }
}

variable "dlq_alarm_threshold" {
  description = "Number of visible DLQ messages that fires the alarm. A single one is already an incident."
  type        = number
  default     = 1

  validation {
    condition     = var.dlq_alarm_threshold >= 1
    error_message = "The DLQ alarm threshold must be at least 1."
  }
}

variable "alert_email" {
  description = "Alert recipient. Empty means no topic subscription is created."
  type        = string
  default     = ""
}
