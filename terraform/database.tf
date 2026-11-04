resource "aws_dynamodb_table" "orders" {
  #checkov:skip=CKV_AWS_28:PITR is enabled only in prod, further down in this same resource. Checkov evaluates the literal, not the condition.
  #checkov:skip=CKV_AWS_119:Encryption uses the AWS managed key. A customer managed key costs a dollar a month and there is no own-rotation or per-key audit requirement here.
  name = "${local.name_prefix}-orders"

  # On demand instead of provisioned capacity: event traffic comes in bursts and there is
  # no baseline that justifies reserving capacity. It also costs nothing when idle.
  billing_mode = "PAY_PER_REQUEST"

  # orderId as the partition key and createdAt as the sort key returns an order's full
  # history with a single query. With a simple key it would take a scan, which reads the
  # whole table and degrades as it grows.
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

  # DynamoDB deletes the item at some point after expiresAt, with no write cost.
  # It is the only cheap way to keep the table from growing without bound.
  ttl {
    attribute_name = "expiresAt"
    enabled        = true
  }

  server_side_encryption {
    enabled = true
  }

  # PITR keeps 35 days of continuous backups and is billed per GB. Locally it is pure
  # cost on test data that is destroyed at the end of every run.
  point_in_time_recovery {
    enabled = var.environment == "prod"
  }
}
