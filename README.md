# terraform-localstack-pipeline

Pipeline de eventos de pedidos (EventBridge → SQS → Lambda → DynamoDB) definido con Terraform y probado de punta a punta contra LocalStack, sin cuenta de AWS.

![Arquitectura](docs/arquitectura.svg)

## Correrlo

Requiere Docker, Terraform ≥ 1.9 y Python 3.12.

```bash
pip install -r tests/requirements.txt
make
```

`make` levanta LocalStack, aplica Terraform, corre los tests y destruye todo. Por pasos: `make up init apply test`, y al final `make destroy down`.

## Decisiones

- **DLQ tras 3 fallos, alarma sobre la DLQ.** Un error que el reintento resuelve no es un incidente; un mensaje en la DLQ sí.
- **Idempotente.** SQS entrega al menos una vez; un `PutItem` condicional evita contar un pedido dos veces.
- **Fallos parciales.** Con `ReportBatchItemFailures` vuelve a la cola solo el mensaje malo, no el lote.
- **IAM mínimo.** Un rol por función, sin comodines.
- **Un solo Terraform** para LocalStack y AWS (`use_localstack`), con `tfvars` por entorno. Solo se ejecutó contra LocalStack.

## CI

Lint (`fmt`, `validate`, ruff, checkov), tests unitarios, integración contra LocalStack, gitleaks y trivy.
