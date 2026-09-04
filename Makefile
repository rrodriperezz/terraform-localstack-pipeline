SHELL := /bin/bash

TERRAFORM ?= terraform
PYTHON ?= python3
COMPOSE ?= docker compose

TFDIR := terraform
TFVARS := environments/local.tfvars
ENDPOINT ?= http://localhost:4566

.PHONY: all up init apply test destroy down fmt validate clean
.DEFAULT_GOAL := all

# Ciclo completo desde cero y vuelta a cero. Es lo que corre CI y lo que tiene que
# terminar en verde en una maquina limpia.
all: up init apply test destroy down

up:
	$(COMPOSE) up -d
	@echo "esperando el healtcheck de localstack"
	@for intento in $$(seq 1 60); do \
		if curl -sf $(ENDPOINT)/_localstack/health >/dev/null 2>&1; then \
			echo "localstack responde en $(ENDPOINT)"; \
			exit 0; \
		fi; \
		sleep 2; \
	done; \
	echo "localstack no llego a estado sano"; \
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

# No toca el estado ni los contenedores: solo lo que se puede regenerar sin costo.
clean:
	rm -rf $(TFDIR)/.build
	rm -rf .pytest_cache .ruff_cache
	find . -type d -name __pycache__ -prune -exec rm -rf {} +
