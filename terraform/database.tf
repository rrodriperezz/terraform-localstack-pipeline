resource "aws_dynamodb_table" "orders" {
  #checkov:skip=CKV_AWS_28:PITR se habilita solo en prod, mas abajo en este mismo recurso. Checkov evalua el literal y no la condicion.
  #checkov:skip=CKV_AWS_119:El cifrado usa la clave administrada por AWS. Una CMK propia cuesta un dolar por mes y aca no hay requisito de rotacion propia ni de auditoria por clave.
  name = "${local.name_prefix}-orders"

  # Bajo demanda y no capacidad provisionada: el trafico de eventos es a rafagas y no hay
  # una linea base que justifique reservar capacidad. Ademas cuesta cero cuando no se usa.
  billing_mode = "PAY_PER_REQUEST"

  # orderId como clave de particion y createdAt como clave de ordenamiento permite traer
  # el hisotrial completo de un pedido con una sola query. Con una clave simple habria que
  # recurrir a scan, que lee la tabla entera y se degrada a medida que crece.
  hash_key  = "orderId"
  range_key = "createdAt"

  attribute {
    name = "orderId"
    type = "S"
  }

  attribute {
    name = "createdAt"
    type = "S"
  }

  # DynamoDB borra el item en algun momento despues de expiresAt, sin costo de escritura.
  # Es la unica forma barata de que la tabla no crezca sin limite.
  ttl {
    attribute_name = "expiresAt"
    enabled        = true
  }

  server_side_encryption {
    enabled = true
  }

  # PITR guarda 35 dias de backups continuos y se cobra por GB. En local es gasto puro
  # sobre datos de prueba que se destruyen al terminar cada corrida.
  point_in_time_recovery {
    enabled = var.environment == "prod"
  }
}
