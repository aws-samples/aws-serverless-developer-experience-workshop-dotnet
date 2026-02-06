# Makefile for Unicorn Contracts Service Infrastructure

# Variables
STAGE ?= local
REGION ?= ap-southeast-2
TERRAFORM_STATE_BUCKET ?=
TERRAFORM_LOCK_TABLE = uni-prop-terraform-locks
AWS_ACCOUNT_ID := $(shell aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
TF_VARS = -var="stage=$(STAGE)" -var="region=$(REGION)"

TERRAFORM_DIR_DOMAIN = Infrastructure/domain
TERRAFORM_DIR_SCHEMA = Infrastructure/schema-registry/ContractStatusChanged
TERRAFORM_DIR_SERVICE = Infrastructure/contracts-service

.PHONY: help build deploy deploy-domain deploy-schema deploy-service test lint clean delete init-domain init-schema init-service init plan plan-domain plan-schema plan-service ensure-state-backend

help: ## Show available commands
	@echo "Unicorn Contracts Service Infrastructure"
	@echo ""
	@echo "Usage: make [target] [STAGE=local|dev|prod] [REGION=ap-southeast-2]"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-15s %s\n", $$1, $$2}'

ensure-state-backend: ## Ensure Terraform state bucket and lock table exist
	@if [ -z "$(TERRAFORM_STATE_BUCKET)" ]; then \
		BUCKET_NAME="uni-prop-terraform-state-$(AWS_ACCOUNT_ID)-$(REGION)"; \
	else \
		BUCKET_NAME="$(TERRAFORM_STATE_BUCKET)"; \
	fi; \
	echo "Checking state bucket: $$BUCKET_NAME"; \
	if ! aws s3api head-bucket --bucket "$$BUCKET_NAME" --region $(REGION) 2>/dev/null; then \
		echo "Creating Terraform state bucket: $$BUCKET_NAME"; \
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
	@echo "Initializing Terraform for $(1)..."
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
		-backend-config="bucket=$$BUCKET_NAME" \
		-backend-config="key=uni-prop-$(STAGE)-contracts-$(1).tfstate" \
		-backend-config="region=$(REGION)" \
		-backend-config="dynamodb_table=$(TERRAFORM_LOCK_TABLE)"
endef

init-domain: ## Initialize Terraform for domain
	$(call tf_init,domain,$(TERRAFORM_DIR_DOMAIN))

init-schema: ## Initialize Terraform for schema registry
	$(call tf_init,schema,$(TERRAFORM_DIR_SCHEMA))

init-service: ## Initialize Terraform for contracts service
	$(call tf_init,service,$(TERRAFORM_DIR_SERVICE))

init: init-domain init-schema init-service ## Initialize Terraform for all components

build: ## Build the application
	@echo "Building .NET application..."
	@dotnet restore ContractsService/ContractsService.csproj
	@dotnet restore ContractsService.Test/ContractsService.Tests.csproj
	@dotnet build ContractsService/ContractsService.csproj

deploy-domain: init-domain ## Deploy domain resources (EventBridge, Schema Registry)
	@echo "Deploying domain resources..."
	@cd $(TERRAFORM_DIR_DOMAIN) && terraform apply $(TF_VARS) -auto-approve

deploy-schema: init-schema ## Deploy event schema
	@echo "Deploying event schema..."
	@cd $(TERRAFORM_DIR_SCHEMA) && terraform apply $(TF_VARS) -auto-approve

deploy-service: init-service build ## Deploy service resources (Lambda, API Gateway, DynamoDB)
	@echo "Deploying service resources..."
	@cd $(TERRAFORM_DIR_SERVICE) && terraform apply $(TF_VARS) -auto-approve

deploy: deploy-domain deploy-schema deploy-service ## Deploy all infrastructure and application

plan-domain: init-domain ## Plan domain resources
	@cd $(TERRAFORM_DIR_DOMAIN) && terraform plan $(TF_VARS)

plan-schema: init-schema ## Plan event schema
	@cd $(TERRAFORM_DIR_SCHEMA) && terraform plan $(TF_VARS)

plan-service: init-service ## Plan service resources
	@cd $(TERRAFORM_DIR_SERVICE) && terraform plan $(TF_VARS)

plan: plan-domain plan-schema plan-service ## Plan all infrastructure

test: ## Run tests
	@echo "Running tests..."
	@dotnet test ContractsService.Test/ContractsService.Tests.csproj

lint: ## Validate Terraform configurations
	@echo "Validating Terraform configurations..."
	@cd $(TERRAFORM_DIR_DOMAIN) && terraform validate
	@cd $(TERRAFORM_DIR_SCHEMA) && terraform validate
	@cd $(TERRAFORM_DIR_SERVICE) && terraform validate

clean: ## Clean build artifacts
	@echo "Cleaning build artifacts..."
	@dotnet clean

delete: ## Destroy all infrastructure in reverse order
	@echo "Destroying infrastructure in reverse order..."
	@cd $(TERRAFORM_DIR_SERVICE) && terraform destroy $(TF_VARS) -auto-approve || true
	@cd $(TERRAFORM_DIR_SCHEMA) && terraform destroy $(TF_VARS) -auto-approve || true
	@cd $(TERRAFORM_DIR_DOMAIN) && terraform destroy $(TF_VARS) -auto-approve || true
	@echo "All infrastructure destroyed"
