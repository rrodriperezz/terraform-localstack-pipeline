# terraform-localstack-pipeline

Order event pipeline (EventBridge → SQS → Lambda → DynamoDB) defined with Terraform and tested end to end against LocalStack, with no AWS account.

![Architecture](docs/architecture.svg)

## Run it

Requires Docker, Terraform ≥ 1.9 and Python 3.12.

```bash
pip install -r tests/requirements.txt
make
```

`make` starts LocalStack, applies Terraform, runs the tests and destroys everything. Step by step: `make up init apply test`, and at the end `make destroy down`.

## Design decisions

- **DLQ after 3 failures, alarm on the DLQ.** An error that a retry fixes is not an incident; a message in the DLQ is.
- **Idempotent.** SQS delivers at least once; a conditional `PutItem` keeps an order from being counted twice.
- **Partial failures.** With `ReportBatchItemFailures` only the bad message goes back to the queue, not the whole batch.
- **Least-privilege IAM.** One role per function, no wildcards.
- **One Terraform codebase** for LocalStack and AWS (`use_localstack`), with per-environment `tfvars`. It has only been run against LocalStack.

## CI

Lint (`fmt`, `validate`, ruff, checkov), unit tests, integration tests against LocalStack, gitleaks and trivy.
