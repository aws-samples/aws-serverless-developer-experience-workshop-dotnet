# Makefile for Unicorn Approvals Service Infrastructure

# Variables
STAGE ?= local
REGION ?= ap-southeast-2
TERRAFORM_STATE_BUCKET ?=
TERRAFORM_LOCK_TABLE = uni-prop-terraform-locks
AWS_ACCOUNT_ID := $(shell aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
TF_VARS = -var="stage=$(STAGE)" -var="region=$(REGION)"

TERRAFORM_DIR_DOMAIN = Infrastructure/domain
TERRAFORM_DIR_SCHEMA = Infrastructure/schema-registry/PublicationEvaluationCompleted
TERRAFORM_DIR_SERVICE = Infrastructure/approvals-service
TERRAFORM_DIR_SUB_CONTRACTS = Infrastructure/subscriptions/contracts
TERRAFORM_DIR_SUB_WEB = Infrastructure/subscriptions/web

.PHONY: help build deploy deploy-domain deploy-schema deploy-service deploy-subscriptions deploy-contracts-subscriptions deploy-web-subscriptions test lint clean delete init-domain init-schema init-service init-sub-contracts init-sub-web init plan plan-domain plan-schema plan-service plan-sub-contracts plan-sub-web ensure-state-backend

help: ## Show available commands
	@echo "Unicorn Approvals Service Infrastructure"
	@echo ""
	@echo "Usage: make [target] [STAGE=local|dev|prod] [REGION=ap-southeast-2]"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-15s %s\n", $1, $2}'

ensure-state-backend: ## Ensure Terraform state bucket and lock table exist
	@if [ -z "$(TERRAFORM_STATE_BUCKET)" ]; then \
		BUCKET_NAME="uni-prop-terraform-state-$(AWS_ACCOUNT_ID)-$(REGION)"; \
	else \
		BUCKET_NAME="$(TERRAFORM_STATE_BUCKET)"; \
	fi; \
	echo "Checking state bucket: $BUCKET_NAME"; \
	if ! aws s3api head-bucket --bucket "$BUCKET_NAME" --region $(REGION) 2>/dev/null; then \
		echo "Creating Terraform state bucket: $BUCKET_NAME"; \
		if [ "$(REGION)" = "us-east-1" ]; then \
			aws s3api create-bucket \
				--bucket "$BUCKET_NAME" \
				--region $(REGION); \
		else \
			aws s3api create-bucket \
				--bucket "$BUCKET_NAME" \
				--region $(REGION) \
				--create-bucket-configuration LocationConstraint=$(REGION); \
		fi; \
		aws s3api put-bucket-versioning \
			--bucket "$BUCKET_NAME" \
			--versioning-configuration Status=Enabled \
			--region $(REGION); \
		echo "Created state bucket: $BUCKET_NAME"; \
	else \
		echo "State bucket already exists: $BUCKET_NAME"; \
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
	if ! aws s3api head-bucket --bucket "$BUCKET_NAME" --region $(REGION) 2>/dev/null; then \
		echo "State bucket not found. Run 'make ensure-state-backend' first."; \
		exit 1; \
	fi; \
	cd $(2) && terraform init \
		-reconfigure \
		-backend-config="bucket=$BUCKET_NAME" \
		-backend-config="key=uni-prop-$(STAGE)-approvals-$(1).tfstate" \
		-backend-config="region=$(REGION)" \
		-backend-config="dynamodb_table=$(TERRAFORM_LOCK_TABLE)"
endef

init-domain: ## Initialize Terraform for domain
	$(call tf_init,domain,$(TERRAFORM_DIR_DOMAIN))

init-schema: ## Initialize Terraform for schema registry
	$(call tf_init,schema,$(TERRAFORM_DIR_SCHEMA))

init-service: ## Initialize Terraform for approvals service
	$(call tf_init,service,$(TERRAFORM_DIR_SERVICE))

init-sub-contracts: ## Initialize Terraform for contracts subscriptions
	$(call tf_init,sub-contracts,$(TERRAFORM_DIR_SUB_CONTRACTS))

init-sub-web: ## Initialize Terraform for web subscriptions
	$(call tf_init,sub-web,$(TERRAFORM_DIR_SUB_WEB))

init: init-domain init-schema init-service init-sub-contracts init-sub-web ## Initialize Terraform for all components

build: ## Build the application
	@echo "Building .NET application..."
	@dotnet restore ApprovalsService/ApprovalsService.csproj
	@dotnet restore ApprovalsService.Tests/ApprovalsService.Tests.csproj
	@dotnet build ApprovalsService/ApprovalsService.csproj

deploy-domain: init-domain ## Deploy domain resources (EventBridge, Schema Registry)
	@echo "Deploying domain resources..."
	@cd $(TERRAFORM_DIR_DOMAIN) && terraform apply $(TF_VARS) -auto-approve

deploy-schema: init-schema ## Deploy event schema
	@echo "Deploying event schema..."
	@cd $(TERRAFORM_DIR_SCHEMA) && terraform apply $(TF_VARS) -auto-approve

deploy-service: init-service build ## Deploy service resources (Lambda, Step Functions, DynamoDB)
	@echo "Deploying service resources..."
	@cd $(TERRAFORM_DIR_SERVICE) && terraform apply $(TF_VARS) -auto-approve

deploy-contracts-subscriptions: init-sub-contracts ## Deploy contracts event subscriptions
	@echo "Deploying contracts subscriptions..."
	@cd $(TERRAFORM_DIR_SUB_CONTRACTS) && terraform apply $(TF_VARS) -auto-approve

deploy-web-subscriptions: init-sub-web ## Deploy web event subscriptions
	@echo "Deploying web subscriptions..."
	@cd $(TERRAFORM_DIR_SUB_WEB) && terraform apply $(TF_VARS) -auto-approve

deploy-subscriptions: deploy-contracts-subscriptions deploy-web-subscriptions ## Deploy all event subscriptions

deploy: deploy-domain deploy-schema deploy-service deploy-subscriptions ## Deploy all infrastructure and application

plan-domain: init-domain ## Plan domain resources
	@cd $(TERRAFORM_DIR_DOMAIN) && terraform plan $(TF_VARS)

plan-schema: init-schema ## Plan event schema
	@cd $(TERRAFORM_DIR_SCHEMA) && terraform plan $(TF_VARS)

plan-service: init-service ## Plan service resources
	@cd $(TERRAFORM_DIR_SERVICE) && terraform plan $(TF_VARS)

plan-sub-contracts: init-sub-contracts ## Plan contracts subscriptions
	@cd $(TERRAFORM_DIR_SUB_CONTRACTS) && terraform plan $(TF_VARS)

plan-sub-web: init-sub-web ## Plan web subscriptions
	@cd $(TERRAFORM_DIR_SUB_WEB) && terraform plan $(TF_VARS)

plan: plan-domain plan-schema plan-service plan-sub-contracts plan-sub-web ## Plan all infrastructure

test: ## Run tests
	@echo "Running tests..."
	@dotnet test ApprovalsService.Tests/ApprovalsService.Tests.csproj

lint: ## Validate Terraform configurations
	@echo "Validating Terraform configurations..."
	@cd $(TERRAFORM_DIR_DOMAIN) && terraform validate
	@cd $(TERRAFORM_DIR_SCHEMA) && terraform validate
	@cd $(TERRAFORM_DIR_SERVICE) && terraform validate
	@cd $(TERRAFORM_DIR_SUB_CONTRACTS) && terraform validate
	@cd $(TERRAFORM_DIR_SUB_WEB) && terraform validate

clean: ## Clean build artifacts
	@echo "Cleaning build artifacts..."
	@dotnet clean

delete: ## Destroy all infrastructure in reverse order
	@echo "Destroying infrastructure in reverse order..."
	@cd $(TERRAFORM_DIR_SUB_WEB) && terraform destroy $(TF_VARS) -auto-approve || true
	@cd $(TERRAFORM_DIR_SUB_CONTRACTS) && terraform destroy $(TF_VARS) -auto-approve || true
	@cd $(TERRAFORM_DIR_SERVICE) && terraform destroy $(TF_VARS) -auto-approve || true
	@cd $(TERRAFORM_DIR_SCHEMA) && terraform destroy $(TF_VARS) -auto-approve || true
	@cd $(TERRAFORM_DIR_DOMAIN) && terraform destroy $(TF_VARS) -auto-approve || true
	@echo "All infrastructure destroyed"
