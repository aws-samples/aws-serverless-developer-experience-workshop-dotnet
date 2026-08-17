# Makefile for Unicorn Web Service Infrastructure

# Variables
STAGE ?= local
REGION ?= ap-southeast-2
TERRAFORM_STATE_BUCKET ?=
TERRAFORM_LOCK_TABLE = uni-prop-terraform-locks
SAM_CMD ?= sam
CONFIRM_PROD ?=
AWS_ACCOUNT_ID = $(shell aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
TF_VARS = -var="stage=$(STAGE)" -var="region=$(REGION)"

TERRAFORM_DIR_DOMAIN = Infrastructure/domain
TERRAFORM_DIR_SCHEMA = Infrastructure/schema-registry/PublicationApprovalRequested
TERRAFORM_DIR_SERVICE = Infrastructure/web-service
TERRAFORM_DIR_SUB_APPROVALS = Infrastructure/subscriptions/approvals

.PHONY: help build local-invoke deploy deploy-domain deploy-schema deploy-service deploy-subscriptions test lint clean delete init-domain init-schema init-service init-sub-approvals init plan plan-domain plan-schema plan-service plan-sub-approvals ensure-state-backend

help: ## Show available commands
	@echo "Unicorn Web Service Infrastructure"
	@echo ""
	@echo "Usage: make [target] [STAGE=local|dev|prod] [REGION=ap-southeast-2]"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-15s %s\n", $$1, $$2}'

ensure-state-backend: ## Ensure state bucket and lock table exist
	@if [ -z "$(TERRAFORM_STATE_BUCKET)" ]; then \
		BUCKET_NAME="uni-prop-terraform-state-$(AWS_ACCOUNT_ID)-$(REGION)"; \
	else \
		BUCKET_NAME="$(TERRAFORM_STATE_BUCKET)"; \
	fi; \
	echo "Checking state bucket: $$BUCKET_NAME"; \
	if ! aws s3api head-bucket --bucket "$$BUCKET_NAME" --region $(REGION) 2>/dev/null; then \
		echo "Creating state bucket: $$BUCKET_NAME"; \
		if [ "$(REGION)" = "us-east-1" ]; then \
			aws s3api create-bucket \
				--bucket "$$BUCKET_NAME" \
				--region $(REGION); \
		else \
			aws s3api create-bucket \
				--bucket "$$BUCKET_NAME" \
				--region $(REGION) \
				--create-bucket-configuration LocationConstraint=$(REGION); \
		fi; \
		aws s3api put-bucket-versioning \
			--bucket "$$BUCKET_NAME" \
			--versioning-configuration Status=Enabled \
			--region $(REGION); \
		echo "Created state bucket: $$BUCKET_NAME"; \
	else \
		echo "State bucket already exists: $$BUCKET_NAME"; \
	fi; \
	echo "Checking lock table: $(TERRAFORM_LOCK_TABLE)"; \
	if ! aws dynamodb describe-table --table-name "$(TERRAFORM_LOCK_TABLE)" --region $(REGION) >/dev/null 2>&1; then \
		echo "Creating DynamoDB lock table: $(TERRAFORM_LOCK_TABLE)"; \
		aws dynamodb create-table \
			--table-name "$(TERRAFORM_LOCK_TABLE)" \
			--attribute-definitions AttributeName=LockID,AttributeType=S \
			--key-schema AttributeName=LockID,KeyType=HASH \
			--billing-mode PAY_PER_REQUEST \
			--region $(REGION); \
		aws dynamodb wait table-exists \
			--table-name "$(TERRAFORM_LOCK_TABLE)" \
			--region $(REGION); \
		echo "Created lock table: $(TERRAFORM_LOCK_TABLE)"; \
	else \
		echo "Lock table already exists: $(TERRAFORM_LOCK_TABLE)"; \
	fi

define tf_init
	@echo "Initializing for $(1)..."
	@if [ -z "$(TERRAFORM_STATE_BUCKET)" ]; then \
		BUCKET_NAME="uni-prop-terraform-state-$(AWS_ACCOUNT_ID)-$(REGION)"; \
	else \
		BUCKET_NAME="$(TERRAFORM_STATE_BUCKET)"; \
	fi; \
	if ! aws s3api head-bucket --bucket "$$BUCKET_NAME" --region $(REGION) 2>/dev/null; then \
		echo "State bucket not found. Run 'make ensure-state-backend' first."; \
		exit 1; \
	fi; \
	cd $(2) && terraform init \
		-reconfigure \
		-backend-config="bucket=$$BUCKET_NAME" \
		-backend-config="key=uni-prop-$(STAGE)-web-$(1).tfstate" \
		-backend-config="region=$(REGION)" \
		-backend-config="dynamodb_table=$(TERRAFORM_LOCK_TABLE)"
endef

define tf_plan
	@if [ "$(STAGE)" = "prod" ]; then \
		cd $(1) && terraform plan $(TF_VARS) -out=.terraform/prod.tfplan; \
	else \
		cd $(1) && terraform plan $(TF_VARS); \
	fi
endef

define tf_apply
	@if [ "$(STAGE)" = "prod" ]; then \
		if [ "$(CONFIRM_PROD)" != "APPLY" ]; then \
			echo "Production apply blocked. Run the prod plan first, review it, then set CONFIRM_PROD=APPLY."; \
			exit 1; \
		fi; \
		if [ ! -f "$(1)/.terraform/prod.tfplan" ]; then \
			echo "Production apply blocked: $(1)/.terraform/prod.tfplan does not exist."; \
			exit 1; \
		fi; \
		cd $(1) && terraform apply .terraform/prod.tfplan; \
	else \
		cd $(1) && terraform apply $(TF_VARS) -auto-approve; \
	fi
endef

define tf_destroy
	@if [ "$(STAGE)" = "prod" ] && [ "$(CONFIRM_PROD)" != "DESTROY" ]; then \
		echo "Production destroy blocked. Review the impact, then set CONFIRM_PROD=DESTROY."; \
		exit 1; \
	fi; \
	cd $(1) && terraform destroy $(TF_VARS) -auto-approve
endef

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
		--output $(TERRAFORM_DIR_SERVICE)/.terraform/search-service.zip
	@python3 ../scripts/package_dotnet_lambda.py \
		--project PublicationManagerService/PublicationManagerService.csproj \
		--build-dir $(TERRAFORM_DIR_SERVICE)/.terraform/build/publication-manager-service \
		--output $(TERRAFORM_DIR_SERVICE)/.terraform/publication-manager-service.zip

check-service-package: ## Verify the reviewed Lambda ZIPs are available for a saved production plan
	@for package in search-service.zip publication-manager-service.zip; do \
		if [ ! -f "$(TERRAFORM_DIR_SERVICE)/.terraform/$$package" ]; then \
			echo "Production apply blocked: reviewed Web Lambda ZIP $$package is missing."; \
			exit 1; \
		fi; \
	done

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
	$(call tf_apply,$(TERRAFORM_DIR_SERVICE))

deploy-subscriptions: init-sub-approvals ## Deploy event subscriptions
	@echo "Deploying approvals subscriptions..."
	$(call tf_apply,$(TERRAFORM_DIR_SUB_APPROVALS))

deploy: deploy-domain deploy-schema deploy-service deploy-subscriptions ## Deploy all infrastructure and application

plan-domain: init-domain ## Plan domain resources
	$(call tf_plan,$(TERRAFORM_DIR_DOMAIN))

plan-schema: init-schema ## Plan event schema
	$(call tf_plan,$(TERRAFORM_DIR_SCHEMA))

plan-service: init-service package-service ## Plan service resources with the exact deployment ZIPs
	$(call tf_plan,$(TERRAFORM_DIR_SERVICE))

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

delete: ## Destroy all infrastructure in reverse order
	@echo "Destroying infrastructure in reverse order..."
	$(call tf_destroy,$(TERRAFORM_DIR_SUB_APPROVALS))
	$(call tf_destroy,$(TERRAFORM_DIR_SERVICE))
	$(call tf_destroy,$(TERRAFORM_DIR_SCHEMA))
	$(call tf_destroy,$(TERRAFORM_DIR_DOMAIN))
	@echo "All infrastructure destroyed"
