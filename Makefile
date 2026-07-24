SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

# Silence every recipe globally (no need for @ on each line).
.SILENT:

GREEN := \033[0;32m
RESET := \033[0m

.PHONY: help check-tools prometheus-connect grafana-open deploy-terraform deploy-app destroy-terraform status stress-test

help: ## Show this help
	printf "$(GREEN)Available targets:$(RESET)\n"
	grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[0;32m%-20s\033[0m %s\n", $$1, $$2}'

check-tools: ## Check that required tools are installed
	bash scripts/check-tools.sh

prometheus-connect: check-tools ## SSH into the Prometheus VM
	bash scripts/prometheus-connect.sh

grafana-open: check-tools ## Print the Grafana dashboard URL
	bash scripts/grafana-open.sh

deploy-terraform: check-tools ## Deploy the infrastructure then the app code
	bash scripts/deploy-terraform.sh
	$(MAKE) deploy-app

deploy-app: check-tools ## Push the Flask app code to the App Service
	bash scripts/deploy-app.sh

destroy-terraform: check-tools ## Destroy all managed resources (tfstate blob kept)
	bash scripts/destroy-terraform.sh

status: check-tools ## Show deployed resource count and endpoints
	bash scripts/status.sh

stress-test: check-tools ## Hammer /error and /crash to trigger the alerts
	bash scripts/stress-test.sh
