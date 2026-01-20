# Makefile for Unicorn Shared Infrastructure

# Variables
STAGE ?= local
REGION ?= ap-southeast-2
TERRAFORM_DIR_NAMESPACES = Infrastructure/namespaces
TERRAFORM_DIR_IMAGES = Infrastructure/images
TERRAFORM_STATE_BUCKET ?= 
AWS_ACCOUNT_ID := $(shell aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")

.PHONY: help deploy-namespaces deploy-images-local deploy-images-dev deploy-images-prod deploy-images deploy delete-namespaces delete-images-local delete-images-dev delete-images-prod delete-images delete list-parameters init-namespaces init-images-local init-images-dev init-images-prod ensure-state-bucket describe-namespaces describe-images-local describe-images-dev describe-images-prod describe-images

help: ## Show available commands
	@echo "Unicorn Shared Infrastructure"
	@echo ""
	@echo "Usage: make [target] [STAGE=local|dev|prod] [REGION=ap-southeast-2]"
	@echo ""
	@echo "Available targets:"
	@echo "  help                      Show available commands"
	@echo "  ensure-state-bucket         Ensure Terraform state bucket exists"
	@echo "  init-namespaces             Initialize Terraform for namespaces"
	@echo "  init-images-local           Initialize Terraform for local images"
	@echo "  init-images-dev             Initialize Terraform for dev images"
	@echo "  init-images-prod            Initialize Terraform for prod images"
	@echo "  deploy-namespaces           Deploy global Unicorn Properties namespaces for all stages"
	@echo "  deploy-images-local         Deploy shared images stack for local environment"
	@echo "  deploy-images-dev           Deploy shared images stack for dev environment"
	@echo "  deploy-images-prod          Deploy shared images stack for prod environment"
	@echo "  deploy-images               Deploy shared images stack for all environments"
	@echo "  deploy                      Deploy all shared infrastructure"
	@echo "  describe-namespaces         Show Terraform state for namespaces"
	@echo "  describe-images-local       Show Terraform state for local images stack"
	@echo "  describe-images-dev         Show Terraform state for dev images stack"
	@echo "  describe-images-prod        Show Terraform state for prod images stack"
	@echo "  describe-images             Show Terraform state for all images stacks"
	@echo "  list-parameters             List all parameters in the Unicorn Properties namespace"
	@echo "  delete-namespaces           Delete Unicorn Properties namespaces"
	@echo "  delete-images-local         Delete shared images stack for local environment"
	@echo "  delete-images-dev           Delete shared images stack for dev environment"
	@echo "  delete-images-prod          Delete shared images stack for prod environment"
	@echo "  delete-images               Delete all shared images stacks"
	@echo "  delete                      Delete all shared infrastructure"

ensure-state-bucket: ## Ensure Terraform state bucket exists
	@if [ -z "$(TERRAFORM_STATE_BUCKET)" ]; then \
		BUCKET_NAME="uni-prop-terraform-state-$(AWS_ACCOUNT_ID)-$(REGION)"; \
		echo "No TERRAFORM_STATE_BUCKET specified, checking bucket: $$BUCKET_NAME"; \
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
			echo "Created Terraform state bucket: $$BUCKET_NAME"; \
		else \
			echo "Terraform state bucket already exists: $$BUCKET_NAME"; \
		fi; \
	else \
		echo "Using specified Terraform state bucket: $(TERRAFORM_STATE_BUCKET)"; \
	fi

init-namespaces: ## Initialize Terraform for namespaces
	@echo "Initializing Terraform for namespaces..."
	@if [ -z "$(TERRAFORM_STATE_BUCKET)" ]; then \
		BUCKET_NAME="uni-prop-terraform-state-$(AWS_ACCOUNT_ID)-$(REGION)"; \
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
		fi; \
		cd $(TERRAFORM_DIR_NAMESPACES) && terraform init \
			-backend-config="bucket=$$BUCKET_NAME" \
			-backend-config="key=uni-prop-namespaces.tfstate" \
			-backend-config="region=$(REGION)"; \
	else \
		cd $(TERRAFORM_DIR_NAMESPACES) && terraform init \
			-backend-config="bucket=$(TERRAFORM_STATE_BUCKET)" \
			-backend-config="key=uni-prop-namespaces.tfstate" \
			-backend-config="region=$(REGION)"; \
	fi

init-images-local: ## Initialize Terraform for local images
	@echo "Initializing Terraform for local images..."
	@if [ -z "$(TERRAFORM_STATE_BUCKET)" ]; then \
		BUCKET_NAME="uni-prop-terraform-state-$(AWS_ACCOUNT_ID)-$(REGION)"; \
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
		fi; \
		cd $(TERRAFORM_DIR_IMAGES) && terraform init \
			-backend-config="bucket=$$BUCKET_NAME" \
			-backend-config="key=uni-prop-local-images.tfstate" \
			-backend-config="region=$(REGION)"; \
	else \
		cd $(TERRAFORM_DIR_IMAGES) && terraform init \
			-backend-config="bucket=$(TERRAFORM_STATE_BUCKET)" \
			-backend-config="key=uni-prop-local-images.tfstate" \
			-backend-config="region=$(REGION)"; \
	fi

init-images-dev: ## Initialize Terraform for dev images
	@echo "Initializing Terraform for dev images..."
	@if [ -z "$(TERRAFORM_STATE_BUCKET)" ]; then \
		BUCKET_NAME="uni-prop-terraform-state-$(AWS_ACCOUNT_ID)-$(REGION)"; \
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
		fi; \
		cd $(TERRAFORM_DIR_IMAGES) && terraform init \
			-backend-config="bucket=$$BUCKET_NAME" \
			-backend-config="key=uni-prop-dev-images.tfstate" \
			-backend-config="region=$(REGION)"; \
	else \
		cd $(TERRAFORM_DIR_IMAGES) && terraform init \
			-backend-config="bucket=$(TERRAFORM_STATE_BUCKET)" \
			-backend-config="key=uni-prop-dev-images.tfstate" \
			-backend-config="region=$(REGION)"; \
	fi

init-images-prod: ## Initialize Terraform for prod images
	@echo "Initializing Terraform for prod images..."
	@if [ -z "$(TERRAFORM_STATE_BUCKET)" ]; then \
		BUCKET_NAME="uni-prop-terraform-state-$(AWS_ACCOUNT_ID)-$(REGION)"; \
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
		fi; \
		cd $(TERRAFORM_DIR_IMAGES) && terraform init \
			-backend-config="bucket=$$BUCKET_NAME" \
			-backend-config="key=uni-prop-prod-images.tfstate" \
			-backend-config="region=$(REGION)"; \
	else \
		cd $(TERRAFORM_DIR_IMAGES) && terraform init \
			-backend-config="bucket=$(TERRAFORM_STATE_BUCKET)" \
			-backend-config="key=uni-prop-prod-images.tfstate" \
			-backend-config="region=$(REGION)"; \
	fi

deploy-namespaces: init-namespaces ## Deploy global Unicorn Properties namespaces for all stages
	@echo "Deploying global namespaces..."
	@cd $(TERRAFORM_DIR_NAMESPACES) && terraform apply \
		-var="region=$(REGION)" \
		-auto-approve

deploy-images-local: init-images-local ## Deploy shared images stack for local environment
	@echo "Deploying shared images stack for local environment..."
	@cd $(TERRAFORM_DIR_IMAGES) && terraform apply \
		-var="stage=local" \
		-var="region=$(REGION)" \
		-auto-approve

deploy-images-dev: init-images-dev ## Deploy shared images stack for dev environment
	@echo "Deploying shared images stack for dev environment..."
	@cd $(TERRAFORM_DIR_IMAGES) && terraform apply \
		-var="stage=dev" \
		-var="region=$(REGION)" \
		-auto-approve

deploy-images-prod: init-images-prod ## Deploy shared images stack for prod environment
	@echo "Deploying shared images stack for prod environment..."
	@cd $(TERRAFORM_DIR_IMAGES) && terraform apply \
		-var="stage=prod" \
		-var="region=$(REGION)" \
		-auto-approve

deploy-images: deploy-images-local deploy-images-dev deploy-images-prod ## Deploy shared images stack for all environments

deploy: deploy-namespaces deploy-images ## Deploy all shared infrastructure

describe-namespaces: ## Show Terraform state for namespaces
	@echo "Describing namespaces Terraform state..."
	@cd $(TERRAFORM_DIR_NAMESPACES) && terraform show

describe-images-local: init-images-local ## Show Terraform state for local images stack
	@echo "Describing local images Terraform state..."
	@cd $(TERRAFORM_DIR_IMAGES) && terraform show

describe-images-dev: init-images-dev ## Show Terraform state for dev images stack
	@echo "Describing dev images Terraform state..."
	@cd $(TERRAFORM_DIR_IMAGES) && terraform show

describe-images-prod: init-images-prod ## Show Terraform state for prod images stack
	@echo "Describing prod images Terraform state..."
	@cd $(TERRAFORM_DIR_IMAGES) && terraform show

describe-images: describe-images-local describe-images-dev describe-images-prod ## Show Terraform state for all images stacks

list-parameters: ## List all parameters in the Unicorn Properties namespace
	@echo "Listing all Unicorn Properties parameters..."
	@aws ssm get-parameters-by-path \
		--path "/uni-prop" \
		--recursive \
		--with-decryption \
		--query 'Parameters[*].[Name,Value,Type]' \
		--output table \
		--region $(REGION)

delete-namespaces: ## Delete Unicorn Properties namespaces
	@echo "Deleting global namespaces..."
	@cd $(TERRAFORM_DIR_NAMESPACES) && terraform destroy \
		-var="region=$(REGION)" \
		-auto-approve || true

delete-images-local: ## Delete shared images stack for local environment
	@echo "Deleting shared images stack for local environment..."
	@cd $(TERRAFORM_DIR_IMAGES) && terraform destroy \
		-var="stage=local" \
		-var="region=$(REGION)" \
		-auto-approve || true

delete-images-dev: ## Delete shared images stack for dev environment
	@echo "Deleting shared images stack for dev environment..."
	@cd $(TERRAFORM_DIR_IMAGES) && terraform destroy \
		-var="stage=dev" \
		-var="region=$(REGION)" \
		-auto-approve || true

delete-images-prod: ## Delete shared images stack for prod environment
	@echo "Deleting shared images stack for prod environment..."
	@cd $(TERRAFORM_DIR_IMAGES) && terraform destroy \
		-var="stage=prod" \
		-var="region=$(REGION)" \
		-auto-approve || true

delete-images: delete-images-prod delete-images-dev delete-images-local ## Delete all shared images stacks

delete: delete-images delete-namespaces ## Delete all shared infrastructure