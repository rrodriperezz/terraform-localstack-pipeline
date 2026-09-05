provider "aws" {
  region = var.aws_region

  # LocalStack no valida credenciales, pero el proveedor si exije que existan y que
  # tengan el formato de una clave de AWS. Contra la nube real estas quedan en null y
  # las credenciales salen de la cadena estandar (perfil, variables de entorno o rol).
  access_key = var.use_localstack ? "test" : null
  secret_key = var.use_localstack ? "test" : null

  # Las tres llamadas que estas banderas evitan van al endpoint de metadatos o a STS
  # real. Contra LocalStack cuelgan hasta el timeout y hacen lento cada plan.
  skip_credentials_validation = var.use_localstack
  skip_metadata_api_check     = var.use_localstack
  skip_requesting_account_id  = var.use_localstack

  # Un dynamic con lista vacia deja el bloque sin emitir, de modo que el mismo codigo
  # sirve contra AWS real sin bifurcar el provider en dos definiciones.
  dynamic "endpoints" {
    for_each = var.use_localstack ? [1] : []

    # events y logs son los nombres canonicos. cloudwatchevents y cloudwatchlogs son
    # alias historicos de los mismos servicios: declarar ambos hace que el proveedor
    # avise que la combinacion es invalida, y a partir de la version 6 sera un error.
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
