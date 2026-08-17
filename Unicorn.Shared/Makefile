# Makefile for Unicorn Shared Infrastructure

# Variables
STAGE ?= local
REGION ?= ap-southeast-2
TERRAFORM_STATE_BUCKET ?=
TERRAFORM_LOCK_TABLE = uni-prop-terraform-locks
CONFIRM_PROD ?=
AWS_ACCOUNT_ID := $(shell aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")

TERRAFORM_DIR_API_GATEWAY_ACCOUNT = Infrastructure/api-gateway-account
TERRAFORM_DIR_NAMESPACES = Infrastructure/namespaces
TERRAFORM_DIR_IMAGES = Infrastructure/uniprop-images

.PHONY: help ensure-state-backend init-api-gateway-account init-namespaces init-images-local init-images-dev init-images-prod init plan-api-gateway-account plan-namespaces plan-images-local plan-images-dev plan-images-prod plan-images plan deploy-api-gateway-account deploy-namespaces deploy-images-local deploy-images-dev deploy-images-prod deploy-images deploy describe-api-gateway-account describe-namespaces describe-images-local describe-images-dev describe-images-prod describe-images describe list-parameters delete-namespaces delete-images-local delete-images-dev delete-images-prod delete-images delete

help: ## Show available commands
	@echo "Unicorn Shared Infrastructure"
	@echo ""
	@echo "Usage: make [target] [STAGE=local|dev|prod] [REGION=ap-southeast-2]"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-25s %s\n", $$1, $$2}'

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
		-backend-config="key=$(3)" \
		-backend-config="region=$(REGION)" \
		-backend-config="dynamodb_table=$(TERRAFORM_LOCK_TABLE)"
endef

define tf_plan
	@if [ "$(1)" = "prod" ]; then \
		cd $(2) && terraform plan $(3) -out=.terraform/prod.tfplan; \
	else \
		cd $(2) && terraform plan $(3); \
	fi
endef

define tf_apply
	@if [ "$(1)" = "prod" ]; then \
		if [ "$(CONFIRM_PROD)" != "APPLY" ]; then \
			echo "Production apply blocked. Run the prod plan first, review it, then set CONFIRM_PROD=APPLY."; \
			exit 1; \
		fi; \
		if [ ! -f "$(2)/.terraform/prod.tfplan" ]; then \
			echo "Production apply blocked: $(2)/.terraform/prod.tfplan does not exist."; \
			exit 1; \
		fi; \
		cd $(2) && terraform apply .terraform/prod.tfplan; \
	else \
		cd $(2) && terraform apply $(3) -auto-approve; \
	fi
endef

define tf_destroy
	@if [ "$(1)" = "prod" ] && [ "$(CONFIRM_PROD)" != "DESTROY" ]; then \
		echo "Production destroy blocked. Review the impact, then set CONFIRM_PROD=DESTROY."; \
		exit 1; \
	fi; \
	cd $(2) && terraform destroy $(3) -auto-approve
endef

init-api-gateway-account: ## Initialize for the account-level API Gateway logging configuration
	$(call tf_init,api-gateway-account,$(TERRAFORM_DIR_API_GATEWAY_ACCOUNT),uni-prop-$(REGION)-shared-api-gateway-account.tfstate)

init-namespaces: ## Initialize for namespaces
	$(call tf_init,namespaces,$(TERRAFORM_DIR_NAMESPACES),uni-prop-shared-namespaces.tfstate)

init-images-local: ## Initialize for local images
	$(call tf_init,images-local,$(TERRAFORM_DIR_IMAGES),uni-prop-local-shared-images.tfstate)

init-images-dev: ## Initialize for dev images
	$(call tf_init,images-dev,$(TERRAFORM_DIR_IMAGES),uni-prop-dev-shared-images.tfstate)

init-images-prod: ## Initialize for prod images
	$(call tf_init,images-prod,$(TERRAFORM_DIR_IMAGES),uni-prop-prod-shared-images.tfstate)

init: init-api-gateway-account init-namespaces init-images-local init-images-dev init-images-prod ## Initialize all shared components

plan-api-gateway-account: init-api-gateway-account ## Plan account-level API Gateway logging resources
	$(call tf_plan,shared,$(TERRAFORM_DIR_API_GATEWAY_ACCOUNT),-var="region=$(REGION)")

plan-namespaces: init-namespaces ## Plan global Unicorn Properties namespaces
	$(call tf_plan,shared,$(TERRAFORM_DIR_NAMESPACES),-var="region=$(REGION)")

plan-images-local: init-images-local ## Plan shared images for local environment
	$(call tf_plan,local,$(TERRAFORM_DIR_IMAGES),-var="stage=local" -var="region=$(REGION)")

plan-images-dev: init-images-dev ## Plan shared images for dev environment
	$(call tf_plan,dev,$(TERRAFORM_DIR_IMAGES),-var="stage=dev" -var="region=$(REGION)")

plan-images-prod: init-images-prod ## Plan shared images for prod environment and save the plan
	$(call tf_plan,prod,$(TERRAFORM_DIR_IMAGES),-var="stage=prod" -var="region=$(REGION)")

plan-images: plan-images-local plan-images-dev plan-images-prod ## Plan shared images for all environments

plan: plan-api-gateway-account plan-namespaces plan-images ## Plan all shared infrastructure

deploy-api-gateway-account: init-api-gateway-account ## Deploy account-level API Gateway logging resources
	@echo "Deploying account-level API Gateway logging resources..."
	$(call tf_apply,shared,$(TERRAFORM_DIR_API_GATEWAY_ACCOUNT),-var="region=$(REGION)")

deploy-namespaces: init-namespaces ## Deploy global Unicorn Properties namespaces
	@echo "Deploying global namespaces..."
	$(call tf_apply,shared,$(TERRAFORM_DIR_NAMESPACES),-var="region=$(REGION)")

deploy-images-local: init-images-local ## Deploy shared images for local environment
	@echo "Deploying shared images stack for local environment..."
	$(call tf_apply,local,$(TERRAFORM_DIR_IMAGES),-var="stage=local" -var="region=$(REGION)")

deploy-images-dev: init-images-dev ## Deploy shared images for dev environment
	@echo "Deploying shared images stack for dev environment..."
	$(call tf_apply,dev,$(TERRAFORM_DIR_IMAGES),-var="stage=dev" -var="region=$(REGION)")

deploy-images-prod: init-images-prod ## Deploy the saved shared images plan for prod environment
	@echo "Deploying shared images stack for prod environment..."
	$(call tf_apply,prod,$(TERRAFORM_DIR_IMAGES),-var="stage=prod" -var="region=$(REGION)")

deploy-images: deploy-images-local deploy-images-dev deploy-images-prod ## Deploy shared images for all environments

deploy: deploy-api-gateway-account deploy-namespaces deploy-images ## Deploy all shared infrastructure

describe-api-gateway-account: init-api-gateway-account ## Show account-level API Gateway logging state
	@echo "Describing account-level API Gateway logging state..."
	@cd $(TERRAFORM_DIR_API_GATEWAY_ACCOUNT) && terraform show

describe-namespaces: init-namespaces ## Show state for namespaces
	@echo "Describing namespaces state..."
	@cd $(TERRAFORM_DIR_NAMESPACES) && terraform show

describe-images-local: init-images-local ## Show state for local images
	@echo "Describing local images state..."
	@cd $(TERRAFORM_DIR_IMAGES) && terraform show

describe-images-dev: init-images-dev ## Show state for dev images
	@echo "Describing dev images state..."
	@cd $(TERRAFORM_DIR_IMAGES) && terraform show

describe-images-prod: init-images-prod ## Show state for prod images
	@echo "Describing prod images state..."
	@cd $(TERRAFORM_DIR_IMAGES) && terraform show

describe-images: describe-images-local describe-images-dev describe-images-prod ## Show state for all images

describe: describe-api-gateway-account describe-namespaces describe-images ## Show state for all shared infrastructure

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
	$(call tf_destroy,shared,$(TERRAFORM_DIR_NAMESPACES),-var="region=$(REGION)")

delete-images-local: init-images-local ## Delete shared images for local environment
	@echo "Deleting shared images stack for local environment..."
	$(call tf_destroy,local,$(TERRAFORM_DIR_IMAGES),-var="stage=local" -var="region=$(REGION)")

delete-images-dev: init-images-dev ## Delete shared images for dev environment
	@echo "Deleting shared images stack for dev environment..."
	$(call tf_destroy,dev,$(TERRAFORM_DIR_IMAGES),-var="stage=dev" -var="region=$(REGION)")

delete-images-prod: init-images-prod ## Delete shared images for prod environment
	@echo "Deleting shared images stack for prod environment..."
	$(call tf_destroy,prod,$(TERRAFORM_DIR_IMAGES),-var="stage=prod" -var="region=$(REGION)")

delete-images: delete-images-prod delete-images-dev delete-images-local ## Delete all shared images stacks

delete: delete-images delete-namespaces ## Delete all shared infrastructure
