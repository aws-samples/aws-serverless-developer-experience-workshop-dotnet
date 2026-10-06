# Makefile for Unicorn Approvals Service Infrastructure

# Variables
STAGE ?= local
REGION ?= ap-southeast-2
TERRAFORM_STATE_BUCKET ?=
TERRAFORM_NAMESPACE = approvals
SAM_CMD ?= sam

TERRAFORM_DIR_DOMAIN = Infrastructure/domain
TERRAFORM_DIR_SCHEMA = Infrastructure/schema-registry/PublicationEvaluationCompleted
TERRAFORM_DIR_SERVICE = Infrastructure/approvals-service
TERRAFORM_DIR_SUB_CONTRACTS = Infrastructure/subscriptions/unicorn-contracts
TERRAFORM_DIR_SUB_WEB = Infrastructure/subscriptions/unicorn-web

.PHONY: help build local-invoke deploy deploy-domain deploy-schema deploy-service deploy-subscriptions deploy-contracts-subscriptions deploy-web-subscriptions test lint clean delete delete-domain delete-schema delete-service delete-subscriptions delete-contracts-subscriptions delete-web-subscriptions init-domain init-schema init-service init-sub-contracts init-sub-web init plan plan-domain plan-schema plan-service plan-sub-contracts plan-sub-web ensure-state-backend

help: ## Show available commands
	@echo "Unicorn Approvals Service Infrastructure"
	@echo ""
	@echo "Usage: make [target] [STAGE=local|dev|prod] [REGION=ap-southeast-2]"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-15s %s\n", $$1, $$2}'

include ../common.mk

init-domain: ensure-state-backend ## Initialize for domain
	$(call tf_init,domain,$(TERRAFORM_DIR_DOMAIN))

init-schema: ensure-state-backend ## Initialize for schema registry
	$(call tf_init,schema,$(TERRAFORM_DIR_SCHEMA))

init-service: ensure-state-backend ## Initialize for approvals service
	$(call tf_init,service,$(TERRAFORM_DIR_SERVICE))

init-sub-contracts: ensure-state-backend ## Initialize for contracts subscriptions
	$(call tf_init,sub-contracts,$(TERRAFORM_DIR_SUB_CONTRACTS))

init-sub-web: ensure-state-backend ## Initialize for web subscriptions
	$(call tf_init,sub-web,$(TERRAFORM_DIR_SUB_WEB))

init: init-domain init-schema init-service init-sub-contracts init-sub-web ## Initialize for all components

build: ## Build Terraform-defined Lambda functions with the SAM Terraform hook
	@echo "Building Approvals Lambda artifacts with AWS SAM..."
	@dotnet restore ApprovalsService/ApprovalsService.csproj
	@dotnet restore ApprovalsService.Tests/ApprovalsService.Tests.csproj
	@TF_VAR_stage=$(STAGE) TF_VAR_region=$(REGION) TF_VAR_sam_build=true \
		TF_VAR_lambda_code_path=$(abspath ApprovalsService) \
		python3 ../scripts/sam_build_terraform.py \
			--terraform-project-root $(TERRAFORM_DIR_SERVICE) \
			--sam-command $(SAM_CMD)

.PHONY: package-service check-service-package

package-service: ## Create the deterministic Lambda ZIP used by Terraform plans
	@echo "Packaging Approvals Lambda deployment artifact..."
	@python3 ../scripts/package_dotnet_lambda.py \
		--project ApprovalsService/ApprovalsService.csproj \
		--build-dir $(TERRAFORM_DIR_SERVICE)/.terraform/build/approvals-service \
		--output $(TERRAFORM_DIR_SERVICE)/.terraform/approvals-service.zip \
		--repo-root .. \
		--source ApprovalsService \
		--source ../Directory.Build.props \
		--source ../global.json \
		--source ../scripts/package_dotnet_lambda.py

check-service-package: ## Verify the reviewed Lambda ZIP and build inputs match the saved production plan
	@python3 ../scripts/check_lambda_package.py \
		--repo-root .. \
		--package-path $(TERRAFORM_DIR_SERVICE)/.terraform/approvals-service.zip \
		--manifest-path $(TERRAFORM_DIR_SERVICE)/.terraform/approvals-service.zip.manifest.json || { \
			echo "Production apply blocked: reviewed Approvals Lambda package is missing or stale. Run 'make package-service' and create a new production plan." >&2; \
			exit 1; \
		}

local-invoke: build ## Invoke a Terraform-defined Lambda locally (FUNCTION may override the default)
	@cd $(TERRAFORM_DIR_SERVICE) && \
		TF_VAR_stage=$(STAGE) TF_VAR_region=$(REGION) \
		$(SAM_CMD) local invoke --hook-name terraform $${FUNCTION:-aws_lambda_function.contract_status_changed_handler} --skip-prepare-infra

deploy-domain: init-domain ## Deploy domain resources (EventBridge, Schema Registry)
	@echo "Deploying domain resources..."
	$(call tf_apply,$(TERRAFORM_DIR_DOMAIN))

deploy-schema: init-schema ## Deploy event schema
	@echo "Deploying event schema..."
	$(call tf_apply,$(TERRAFORM_DIR_SCHEMA))

deploy-service: init-service ## Deploy service resources (Lambda, Step Functions, DynamoDB)
	@if [ "$(STAGE)" = "prod" ]; then \
		$(MAKE) check-service-package; \
	else \
		$(MAKE) package-service; \
	fi
	@echo "Deploying service resources..."
	$(call tf_apply,$(TERRAFORM_DIR_SERVICE),$(TERRAFORM_DIR_SERVICE)/.terraform/approvals-service.zip.manifest.json)

deploy-contracts-subscriptions: init-sub-contracts ## Deploy contracts event subscriptions
	@echo "Deploying contracts subscriptions..."
	$(call tf_apply,$(TERRAFORM_DIR_SUB_CONTRACTS))

deploy-web-subscriptions: init-sub-web ## Deploy web event subscriptions
	@echo "Deploying web subscriptions..."
	$(call tf_apply,$(TERRAFORM_DIR_SUB_WEB))

deploy-subscriptions: deploy-contracts-subscriptions deploy-web-subscriptions ## Deploy all event subscriptions

deploy: deploy-domain deploy-schema deploy-service deploy-subscriptions ## Deploy all infrastructure and application

plan-domain: init-domain ## Plan domain resources
	$(call tf_plan,$(TERRAFORM_DIR_DOMAIN))

plan-schema: init-schema ## Plan event schema
	$(call tf_plan,$(TERRAFORM_DIR_SCHEMA))

plan-service: init-service package-service ## Plan service resources with the exact deployment ZIP
	$(call tf_plan,$(TERRAFORM_DIR_SERVICE),$(TERRAFORM_DIR_SERVICE)/.terraform/approvals-service.zip.manifest.json)

plan-sub-contracts: init-sub-contracts ## Plan contracts subscriptions
	$(call tf_plan,$(TERRAFORM_DIR_SUB_CONTRACTS))

plan-sub-web: init-sub-web ## Plan web subscriptions
	$(call tf_plan,$(TERRAFORM_DIR_SUB_WEB))

plan: plan-domain plan-schema plan-service plan-sub-contracts plan-sub-web ## Plan all infrastructure

test: ## Run tests
	@echo "Running tests..."
	@dotnet test ApprovalsService.Tests/ApprovalsService.Tests.csproj

lint: ## Validate configurations
	@echo "Validating configurations..."
	@cd $(TERRAFORM_DIR_DOMAIN) && terraform validate
	@cd $(TERRAFORM_DIR_SCHEMA) && terraform validate
	@cd $(TERRAFORM_DIR_SERVICE) && terraform validate
	@cd $(TERRAFORM_DIR_SUB_CONTRACTS) && terraform validate
	@cd $(TERRAFORM_DIR_SUB_WEB) && terraform validate

clean: ## Clean build artifacts
	@echo "Cleaning build artifacts..."
	@dotnet clean

delete-web-subscriptions: init-sub-web ## Destroy Web event subscriptions
	@echo "Destroying Web event subscriptions..."
	$(call tf_destroy,$(TERRAFORM_DIR_SUB_WEB))

delete-contracts-subscriptions: init-sub-contracts ## Destroy Contracts event subscriptions
	@echo "Destroying Contracts event subscriptions..."
	$(call tf_destroy,$(TERRAFORM_DIR_SUB_CONTRACTS))

delete-subscriptions: ## Destroy all Approvals event subscriptions
	+$(MAKE) delete-web-subscriptions
	+$(MAKE) delete-contracts-subscriptions

delete-service: init-service ## Destroy approvals service resources
	@echo "Destroying approvals service resources..."
	$(call tf_destroy,$(TERRAFORM_DIR_SERVICE))

delete-schema: init-schema ## Destroy the approvals event schema
	@echo "Destroying approvals event schema..."
	$(call tf_destroy,$(TERRAFORM_DIR_SCHEMA))

delete-domain: init-domain ## Destroy approvals domain resources
	@echo "Destroying approvals domain resources..."
	$(call tf_destroy,$(TERRAFORM_DIR_DOMAIN))

delete: ## Destroy all infrastructure in reverse order
	@echo "Destroying infrastructure in reverse order..."
	+$(MAKE) delete-subscriptions
	+$(MAKE) delete-service
	+$(MAKE) delete-schema
	+$(MAKE) delete-domain
	@echo "All infrastructure destroyed"
