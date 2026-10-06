# Makefile for Unicorn Contracts Service Infrastructure

# Variables
STAGE ?= local
REGION ?= ap-southeast-2
TERRAFORM_STATE_BUCKET ?=
TERRAFORM_NAMESPACE = contracts
SAM_CMD ?= sam

TERRAFORM_DIR_DOMAIN = Infrastructure/domain
TERRAFORM_DIR_SCHEMA = Infrastructure/schema-registry/ContractStatusChanged
TERRAFORM_DIR_SERVICE = Infrastructure/contracts-service

.PHONY: help build local-invoke deploy deploy-domain deploy-schema deploy-service test lint clean delete delete-domain delete-schema delete-service init-domain init-schema init-service init plan plan-domain plan-schema plan-service ensure-state-backend

help: ## Show available commands
	@echo "Unicorn Contracts Service Infrastructure"
	@echo ""
	@echo "Usage: make [target] [STAGE=local|dev|prod] [REGION=ap-southeast-2]"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-15s %s\n", $$1, $$2}'

include ../common.mk

init-domain: ensure-state-backend ## Initialize for domain
	$(call tf_init,domain,$(TERRAFORM_DIR_DOMAIN))

init-schema: ensure-state-backend ## Initialize for schema registry
	$(call tf_init,schema,$(TERRAFORM_DIR_SCHEMA))

init-service: ensure-state-backend ## Initialize for contracts service
	$(call tf_init,service,$(TERRAFORM_DIR_SERVICE))

init: init-domain init-schema init-service ## Initialize for all components

build: ## Build Terraform-defined Lambda functions with the SAM Terraform hook
	@echo "Building Contracts Lambda artifacts with AWS SAM..."
	@dotnet restore ContractsService/ContractsService.csproj
	@dotnet restore ContractsService.Test/ContractsService.Tests.csproj
	@TF_VAR_stage=$(STAGE) TF_VAR_region=$(REGION) TF_VAR_sam_build=true \
		TF_VAR_lambda_code_path=$(abspath ContractsService) \
		python3 ../scripts/sam_build_terraform.py \
			--terraform-project-root $(TERRAFORM_DIR_SERVICE) \
			--sam-command $(SAM_CMD)

.PHONY: package-service check-service-package

package-service: ## Create the deterministic Lambda ZIP used by Terraform plans
	@echo "Packaging Contracts Lambda deployment artifact..."
	@python3 ../scripts/package_dotnet_lambda.py \
		--project ContractsService/ContractsService.csproj \
		--build-dir $(TERRAFORM_DIR_SERVICE)/.terraform/build/contract-event-handler \
		--output $(TERRAFORM_DIR_SERVICE)/.terraform/contract-event-handler.zip \
		--repo-root .. \
		--source ContractsService \
		--source ../Directory.Build.props \
		--source ../global.json \
		--source ../scripts/package_dotnet_lambda.py

check-service-package: ## Verify the reviewed Lambda ZIP and build inputs match the saved production plan
	@python3 ../scripts/check_lambda_package.py \
		--repo-root .. \
		--package-path $(TERRAFORM_DIR_SERVICE)/.terraform/contract-event-handler.zip \
		--manifest-path $(TERRAFORM_DIR_SERVICE)/.terraform/contract-event-handler.zip.manifest.json || { \
			echo "Production apply blocked: reviewed Contracts Lambda package is missing or stale. Run 'make package-service' and create a new production plan." >&2; \
			exit 1; \
		}

local-invoke: build ## Invoke a Terraform-defined Lambda locally (FUNCTION may override the default)
	@cd $(TERRAFORM_DIR_SERVICE) && \
		TF_VAR_stage=$(STAGE) TF_VAR_region=$(REGION) \
		$(SAM_CMD) local invoke --hook-name terraform $${FUNCTION:-aws_lambda_function.contract_event_handler} --skip-prepare-infra

deploy-domain: init-domain ## Deploy domain resources (EventBridge, Schema Registry)
	@echo "Deploying domain resources..."
	$(call tf_apply,$(TERRAFORM_DIR_DOMAIN))

deploy-schema: init-schema ## Deploy event schema
	@echo "Deploying event schema..."
	$(call tf_apply,$(TERRAFORM_DIR_SCHEMA))

deploy-service: init-service ## Deploy service resources (Lambda, API Gateway, DynamoDB)
	@if [ "$(STAGE)" = "prod" ]; then \
		$(MAKE) check-service-package; \
	else \
		$(MAKE) package-service; \
	fi
	@echo "Deploying service resources..."
	$(call tf_apply,$(TERRAFORM_DIR_SERVICE),$(TERRAFORM_DIR_SERVICE)/.terraform/contract-event-handler.zip.manifest.json)

deploy: deploy-domain deploy-schema deploy-service ## Deploy all infrastructure and application

plan-domain: init-domain ## Plan domain resources
	$(call tf_plan,$(TERRAFORM_DIR_DOMAIN))

plan-schema: init-schema ## Plan event schema
	$(call tf_plan,$(TERRAFORM_DIR_SCHEMA))

plan-service: init-service package-service ## Plan service resources with the exact deployment ZIP
	$(call tf_plan,$(TERRAFORM_DIR_SERVICE),$(TERRAFORM_DIR_SERVICE)/.terraform/contract-event-handler.zip.manifest.json)

plan: plan-domain plan-schema plan-service ## Plan all infrastructure

test: ## Run tests
	@echo "Running tests..."
	@dotnet test ContractsService.Test/ContractsService.Tests.csproj

lint: ## Validate configurations
	@echo "Validating configurations..."
	@cd $(TERRAFORM_DIR_DOMAIN) && terraform validate
	@cd $(TERRAFORM_DIR_SCHEMA) && terraform validate
	@cd $(TERRAFORM_DIR_SERVICE) && terraform validate

clean: ## Clean build artifacts
	@echo "Cleaning build artifacts..."
	@dotnet clean

delete-service: init-service ## Destroy contracts service resources
	@echo "Destroying contracts service resources..."
	$(call tf_destroy,$(TERRAFORM_DIR_SERVICE))

delete-schema: init-schema ## Destroy the contracts event schema
	@echo "Destroying contracts event schema..."
	$(call tf_destroy,$(TERRAFORM_DIR_SCHEMA))

delete-domain: init-domain ## Destroy contracts domain resources
	@echo "Destroying contracts domain resources..."
	$(call tf_destroy,$(TERRAFORM_DIR_DOMAIN))

delete: ## Destroy all infrastructure in reverse order
	@echo "Destroying infrastructure in reverse order..."
	+$(MAKE) delete-service
	+$(MAKE) delete-schema
	+$(MAKE) delete-domain
	@echo "All infrastructure destroyed"
