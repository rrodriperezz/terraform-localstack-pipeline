environment    = "local"
use_localstack = true

lambda_memory_mb = 256

# Ten seconds instead of thirty as in prod. The queue's visibility timeout is six times this
# value, and a poison message has to exhaust all three deliveries to land in the DLQ: with
# the prod value that test would take nine minutes. With ten it drops to three, and the
# ratio between both numbers stays exactly the same as in production.
lambda_timeout_seconds = 10

log_retention_days = 1
