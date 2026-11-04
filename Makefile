SHELL := /bin/bash

TERRAFORM ?= terraform
PYTHON ?= python3
COMPOSE ?= docker compose

TFDIR := terraform
TFVARS := environments/local.tfvars
ENDPOINT ?= http://localhost:4566

.PHONY: all up init apply test destroy down fmt validate clean
.DEFAULT_GOAL := all

# Full cycle from zero and back to zero. It is what CI runs and what has to
# finish green on a clean machine.
all: up init apply test destroy down

up:
	$(COMPOSE) up -d
	@echo "waiting for the localstack healthcheck"
	@for attempt in $$(seq 1 60); do \
		if curl -sf $(ENDPOINT)/_localstack/health >/dev/null 2>&1; then \
			echo "localstack is up at $(ENDPOINT)"; \
			exit 0; \
		fi; \
		sleep 2; \
	done; \
	echo "localstack never became healthy"; \
	$(COMPOSE) logs --tail 50 localstack; \
	exit 1

init:
	$(TERRAFORM) -chdir=$(TFDIR) init -input=false

apply:
	$(TERRAFORM) -chdir=$(TFDIR) apply -auto-approve -input=false -var-file=$(TFVARS)

test:
	$(PYTHON) -m pytest tests/ -v

destroy:
	$(TERRAFORM) -chdir=$(TFDIR) destroy -auto-approve -input=false -var-file=$(TFVARS)

down:
	$(COMPOSE) down -v

fmt:
	$(TERRAFORM) fmt -recursive
	$(PYTHON) -m ruff format src tests

validate:
	$(TERRAFORM) fmt -check -recursive
	$(TERRAFORM) -chdir=$(TFDIR) init -backend=false -input=false
	$(TERRAFORM) -chdir=$(TFDIR) validate
	$(PYTHON) -m ruff check src tests

# Does not touch state or containers: only what can be regenerated at no cost.
clean:
	rm -rf $(TFDIR)/.build
	rm -rf .pytest_cache .ruff_cache
	find . -type d -name __pycache__ -prune -exec rm -rf {} +
