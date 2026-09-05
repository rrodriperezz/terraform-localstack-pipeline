environment    = "local"
use_localstack = true

lambda_memory_mb = 256

# Diez segundos y no treinta como en prod. El visibility timeout de la cola es seis veces
# este valor, y un mensaje envenenado necesita agotar las tres entregas para caer en la
# DLQ: con el valor de prod esa prueba tardaria nueve minutos. Con diez baja a tres, y la
# relacion entre ambos numeros sigue siendo exactamente la misma que en produccion.
lambda_timeout_seconds = 10

log_retention_days = 1
