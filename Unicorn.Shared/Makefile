# Makefile for Unicorn Shared Infrastructure

# Variables
STAGE ?= local
REGION ?= ap-southeast-2
TERRAFORM_STATE_BUCKET ?=
TERRAFORM_LOCK_TABLE = uni-prop-terraform-locks
AWS_ACCOUNT_ID := $(shell aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")

TERRAFORM_DIR_NAMESPACES = Infrastructure/namespaces
TERRAFORM_DIR_IMAGES = Infrastructure/images

.PHONY: help deploy-namespaces deploy-images-local deploy-images-dev deploy-images-prod deploy-images deploy delete-namespaces delete-images-local delete-images-dev delete-images-prod delete-images delete list-parameters init-namespaces init-images-local init-images-dev init-images-prod ensure-state-backend describe-namespaces describe-images-local describe-images-dev describe-images-prod describe-images

help: ## Show available commands
	@echo "Unicorn Shared Infrastructure"
	@echo ""
	@echo "Usage: make [target] [STAGE=local|dev|prod] [REGION=ap-southeast-2]"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-25s %s\n", $$1, $$2}'

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
		-reconfigure \
		-backend-config="bucket=$$BUCKET_NAME" \
		-backend-config="key=$(3)" \
		-backend-config="region=$(REGION)" \
		-backend-config="dynamodb_table=$(TERRAFORM_LOCK_TABLE)"
endef

init-namespaces: ## Initialize Terraform for namespaces
	$(call tf_init,namespaces,$(TERRAFORM_DIR_NAMESPACES),uni-prop-shared-namespaces.tfstate)

init-images-local: ## Initialize Terraform for local images
	$(call tf_init,images-local,$(TERRAFORM_DIR_IMAGES),uni-prop-local-shared-images.tfstate)

init-images-dev: ## Initialize Terraform for dev images
	$(call tf_init,images-dev,$(TERRAFORM_DIR_IMAGES),uni-prop-dev-shared-images.tfstate)

init-images-prod: ## Initialize Terraform for prod images
	$(call tf_init,images-prod,$(TERRAFORM_DIR_IMAGES),uni-prop-prod-shared-images.tfstate)

deploy-namespaces: init-namespaces ## Deploy global Unicorn Properties namespaces
	@echo "Deploying global namespaces..."
	@cd $(TERRAFORM_DIR_NAMESPACES) && terraform apply \
		-var="region=$(REGION)" \
		-auto-approve

deploy-images-local: init-images-local ## Deploy shared images for local environment
	@echo "Deploying shared images stack for local environment..."
	@cd $(TERRAFORM_DIR_IMAGES) && terraform apply \
		-var="stage=local" \
		-var="region=$(REGION)" \
		-auto-approve

deploy-images-dev: init-images-dev ## Deploy shared images for dev environment
	@echo "Deploying shared images stack for dev environment..."
	@cd $(TERRAFORM_DIR_IMAGES) && terraform apply \
		-var="stage=dev" \
		-var="region=$(REGION)" \
		-auto-approve

deploy-images-prod: init-images-prod ## Deploy shared images for prod environment
	@echo "Deploying shared images stack for prod environment..."
	@cd $(TERRAFORM_DIR_IMAGES) && terraform apply \
		-var="stage=prod" \
		-var="region=$(REGION)" \
		-auto-approve

deploy-images: deploy-images-local deploy-images-dev deploy-images-prod ## Deploy shared images for all environments

deploy: deploy-namespaces deploy-images ## Deploy all shared infrastructure

describe-namespaces: init-namespaces ## Show Terraform state for namespaces
	@echo "Describing namespaces Terraform state..."
	@cd $(TERRAFORM_DIR_NAMESPACES) && terraform show

describe-images-local: init-images-local ## Show Terraform state for local images
	@echo "Describing local images Terraform state..."
	@cd $(TERRAFORM_DIR_IMAGES) && terraform show

describe-images-dev: init-images-dev ## Show Terraform state for dev images
	@echo "Describing dev images Terraform state..."
	@cd $(TERRAFORM_DIR_IMAGES) && terraform show

describe-images-prod: init-images-prod ## Show Terraform state for prod images
	@echo "Describing prod images Terraform state..."
	@cd $(TERRAFORM_DIR_IMAGES) && terraform show

describe-images: describe-images-local describe-images-dev describe-images-prod ## Show Terraform state for all images

list-parameters: ## List all parameters in the Unicorn Properties namespace
	@echo "Listing all Unicorn Properties parameters..."
	@aws ssm get-parameters-by-path \
		--path "/uni-prop" \
		--recursive \
		--with-decryption \
		--query 'Parameters[*].[Name,Value,Type]' \
		--output table \
		--region $(REGION)

delete-namespaces: init-namespaces ## Delete Unicorn Properties namespaces
	@echo "Deleting global namespaces..."
	@cd $(TERRAFORM_DIR_NAMESPACES) && terraform destroy \
		-var="region=$(REGION)" \
		-auto-approve || true

delete-images-local: init-images-local ## Delete shared images for local environment
	@echo "Deleting shared images stack for local environment..."
	@cd $(TERRAFORM_DIR_IMAGES) && terraform destroy \
		-var="stage=local" \
		-var="region=$(REGION)" \
		-auto-approve || true

delete-images-dev: init-images-dev ## Delete shared images for dev environment
	@echo "Deleting shared images stack for dev environment..."
	@cd $(TERRAFORM_DIR_IMAGES) && terraform destroy \
		-var="stage=dev" \
		-var="region=$(REGION)" \
		-auto-approve || true

delete-images-prod: init-images-prod ## Delete shared images for prod environment
	@echo "Deleting shared images stack for prod environment..."
	@cd $(TERRAFORM_DIR_IMAGES) && terraform destroy \
		-var="stage=prod" \
		-var="region=$(REGION)" \
		-auto-approve || true

delete-images: delete-images-prod delete-images-dev delete-images-local ## Delete all shared images stacks

delete: delete-images delete-namespaces ## Delete all shared infrastructure
