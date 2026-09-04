variable "project_name" {
  description = "Prefijo de todos los recursos. Junto con environment forma name_prefix."
  type        = string
  default     = "order-events"
}

variable "environment" {
  description = "Entorno de despliegue. Determina el sufijo de los nombres y si se habilita PITR."
  type        = string

  validation {
    condition     = contains(["local", "prod"], var.environment)
    error_message = "El entorno debe ser local o prod."
  }
}

variable "aws_region" {
  description = "Region de AWS. Contra LocalStack es indistinta, pero forma parte de los ARN."
  type        = string
  default     = "us-east-1"
}

variable "use_localstack" {
  description = "Redirige todos los endpoints del proveedor a LocalStack y saltea la validacion de credenciales."
  type        = bool
  default     = false
}

variable "localstack_endpoint" {
  description = "URL del gateway unico de LocalStack. Solo se usa cuando use_localstack es true."
  type        = string
  default     = "http://localhost:4566"
}

variable "lambda_memory_mb" {
  description = "Memoria de la funcion procesadora. En Lambda la CPU es proporcional a la memoria."
  type        = number
  default     = 256

  validation {
    condition     = var.lambda_memory_mb >= 128 && var.lambda_memory_mb <= 3008
    error_message = "La memoria de la funcion debe estar entre 128 y 3008 MB."
  }
}

variable "lambda_timeout_seconds" {
  description = "Timeout de la funcion. El visibility timeout de la cola se calcula a partir de este valor."
  type        = number
  default     = 30

  validation {
    condition     = var.lambda_timeout_seconds >= 1 && var.lambda_timeout_seconds <= 900
    error_message = "El timeout de la funcion debe estar entre 1 y 900 segudos."
  }
}

variable "log_retention_days" {
  description = "Dias de retencion del log group de la funcion."
  type        = number
  default     = 14

  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 3653
    error_message = "La retencion de logs debe estar entre 1 y 3653 dias."
  }
}

variable "dlq_alarm_threshold" {
  description = "Cantidad de mensajes visibles en la DLQ que dispara la alarma. Uno solo ya es un incidente."
  type        = number
  default     = 1

  validation {
    condition     = var.dlq_alarm_threshold >= 1
    error_message = "El umbral de la alarma de la DLQ debe ser al menos 1."
  }
}

variable "alert_email" {
  description = "Destinatario de las alertas. Vacio no crea la suscripcion al topico."
  type        = string
  default     = ""
}
