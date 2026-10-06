# Makefile for Unicorn Web Service Infrastructure

# Variables
STAGE ?= local
REGION ?= ap-southeast-2
TERRAFORM_STATE_BUCKET ?=
TERRAFORM_NAMESPACE = web
SAM_CMD ?= sam

TERRAFORM_DIR_DOMAIN = Infrastructure/domain
TERRAFORM_DIR_SCHEMA = Infrastructure/schema-registry/PublicationApprovalRequested
TERRAFORM_DIR_SERVICE = Infrastructure/web-service
TERRAFORM_DIR_SUB_APPROVALS = Infrastructure/subscriptions/approvals

.PHONY: help build local-invoke deploy deploy-domain deploy-schema deploy-service deploy-subscriptions test lint clean delete delete-domain delete-schema delete-service delete-subscriptions init-domain init-schema init-service init-sub-approvals init plan plan-domain plan-schema plan-service plan-sub-approvals ensure-state-backend

help: ## Show available commands
	@echo "Unicorn Web Service Infrastructure"
	@echo ""
	@echo "Usage: make [target] [STAGE=local|dev|prod] [REGION=ap-southeast-2]"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-15s %s\n", $$1, $$2}'

include ../common.mk

init-domain: ensure-state-backend ## Initialize for domain
	$(call tf_init,domain,$(TERRAFORM_DIR_DOMAIN))

init-schema: ensure-state-backend ## Initialize for schema registry
	$(call tf_init,schema,$(TERRAFORM_DIR_SCHEMA))

init-service: ensure-state-backend ## Initialize for web service
	$(call tf_init,service,$(TERRAFORM_DIR_SERVICE))

init-sub-approvals: ensure-state-backend ## Initialize for approvals subscriptions
	$(call tf_init,sub-approvals,$(TERRAFORM_DIR_SUB_APPROVALS))

init: init-domain init-schema init-service init-sub-approvals ## Initialize for all components

build: ## Build Terraform-defined Lambda functions with the SAM Terraform hook
	@echo "Building Web Lambda artifacts with AWS SAM..."
	@dotnet restore PublicationManagerService/PublicationManagerService.csproj
	@dotnet restore SearchService/SearchService.csproj
	@dotnet restore PublicationManagerService.Tests/PublicationManagerService.Tests.csproj
	@dotnet restore SearchService.Tests/SearchService.Tests.csproj
	@TF_VAR_stage=$(STAGE) TF_VAR_region=$(REGION) TF_VAR_sam_build=true \
		TF_VAR_search_service_code_path=$(abspath SearchService) \
		TF_VAR_publication_manager_code_path=$(abspath PublicationManagerService) \
		python3 ../scripts/sam_build_terraform.py \
			--terraform-project-root $(TERRAFORM_DIR_SERVICE) \
			--sam-command $(SAM_CMD)

.PHONY: package-service check-service-package

package-service: ## Create the deterministic Lambda ZIPs used by Terraform plans
	@echo "Packaging Web Lambda deployment artifacts..."
	@python3 ../scripts/package_dotnet_lambda.py \
		--project SearchService/SearchService.csproj \
		--build-dir $(TERRAFORM_DIR_SERVICE)/.terraform/build/search-service \
		--output $(TERRAFORM_DIR_SERVICE)/.terraform/search-service.zip \
		--repo-root .. \
		--source SearchService \
		--source Common \
		--source ../Directory.Build.props \
		--source ../global.json \
		--source ../scripts/package_dotnet_lambda.py
	@python3 ../scripts/package_dotnet_lambda.py \
		--project PublicationManagerService/PublicationManagerService.csproj \
		--build-dir $(TERRAFORM_DIR_SERVICE)/.terraform/build/publication-manager-service \
		--output $(TERRAFORM_DIR_SERVICE)/.terraform/publication-manager-service.zip \
		--repo-root .. \
		--source PublicationManagerService \
		--source Common \
		--source ../Directory.Build.props \
		--source ../global.json \
		--source ../scripts/package_dotnet_lambda.py

check-service-package: ## Verify the reviewed Lambda ZIPs and build inputs match the saved production plan
	@python3 ../scripts/check_lambda_package.py \
		--repo-root .. \
		--package-path $(TERRAFORM_DIR_SERVICE)/.terraform/search-service.zip \
		--manifest-path $(TERRAFORM_DIR_SERVICE)/.terraform/search-service.zip.manifest.json || { \
			echo "Production apply blocked: reviewed Web Search Lambda package is missing or stale. Run 'make package-service' and create a new production plan." >&2; \
			exit 1; \
		}
	@python3 ../scripts/check_lambda_package.py \
		--repo-root .. \
		--package-path $(TERRAFORM_DIR_SERVICE)/.terraform/publication-manager-service.zip \
		--manifest-path $(TERRAFORM_DIR_SERVICE)/.terraform/publication-manager-service.zip.manifest.json || { \
			echo "Production apply blocked: reviewed Web Publication Manager Lambda package is missing or stale. Run 'make package-service' and create a new production plan." >&2; \
			exit 1; \
		}

local-invoke: build ## Invoke a Terraform-defined Lambda locally (FUNCTION may override the default)
	@cd $(TERRAFORM_DIR_SERVICE) && \
		TF_VAR_stage=$(STAGE) TF_VAR_region=$(REGION) \
		$(SAM_CMD) local invoke --hook-name terraform $${FUNCTION:-aws_lambda_function.search_function} --skip-prepare-infra

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
	$(call tf_apply,$(TERRAFORM_DIR_SERVICE),$(TERRAFORM_DIR_SERVICE)/.terraform/search-service.zip.manifest.json $(TERRAFORM_DIR_SERVICE)/.terraform/publication-manager-service.zip.manifest.json)

deploy-subscriptions: init-sub-approvals ## Deploy event subscriptions
	@echo "Deploying approvals subscriptions..."
	$(call tf_apply,$(TERRAFORM_DIR_SUB_APPROVALS))

deploy: deploy-domain deploy-schema deploy-service deploy-subscriptions ## Deploy all infrastructure and application

plan-domain: init-domain ## Plan domain resources
	$(call tf_plan,$(TERRAFORM_DIR_DOMAIN))

plan-schema: init-schema ## Plan event schema
	$(call tf_plan,$(TERRAFORM_DIR_SCHEMA))

plan-service: init-service package-service ## Plan service resources with the exact deployment ZIPs
	$(call tf_plan,$(TERRAFORM_DIR_SERVICE),$(TERRAFORM_DIR_SERVICE)/.terraform/search-service.zip.manifest.json $(TERRAFORM_DIR_SERVICE)/.terraform/publication-manager-service.zip.manifest.json)

plan-sub-approvals: init-sub-approvals ## Plan approvals subscriptions
	$(call tf_plan,$(TERRAFORM_DIR_SUB_APPROVALS))

plan: plan-domain plan-schema plan-service plan-sub-approvals ## Plan all infrastructure

test: ## Run tests
	@echo "Running tests..."
	@dotnet test PublicationManagerService.Tests/PublicationManagerService.Tests.csproj
	@dotnet test SearchService.Tests/SearchService.Tests.csproj

lint: ## Validate configurations
	@echo "Validating configurations..."
	@cd $(TERRAFORM_DIR_DOMAIN) && terraform validate
	@cd $(TERRAFORM_DIR_SCHEMA) && terraform validate
	@cd $(TERRAFORM_DIR_SERVICE) && terraform validate
	@cd $(TERRAFORM_DIR_SUB_APPROVALS) && terraform validate

clean: ## Clean build artifacts
	@echo "Cleaning build artifacts..."
	@dotnet clean

delete-subscriptions: init-sub-approvals ## Destroy Approvals event subscriptions
	@echo "Destroying Approvals event subscriptions..."
	$(call tf_destroy,$(TERRAFORM_DIR_SUB_APPROVALS))

delete-service: init-service ## Destroy Web service resources
	@echo "Destroying Web service resources..."
	$(call tf_destroy,$(TERRAFORM_DIR_SERVICE))

delete-schema: init-schema ## Destroy the Web event schema
	@echo "Destroying Web event schema..."
	$(call tf_destroy,$(TERRAFORM_DIR_SCHEMA))

delete-domain: init-domain ## Destroy Web domain resources
	@echo "Destroying Web domain resources..."
	$(call tf_destroy,$(TERRAFORM_DIR_DOMAIN))

delete: ## Destroy all infrastructure in reverse order
	@echo "Destroying infrastructure in reverse order..."
	+$(MAKE) delete-subscriptions
	+$(MAKE) delete-service
	+$(MAKE) delete-schema
	+$(MAKE) delete-domain
	@echo "All infrastructure destroyed"
