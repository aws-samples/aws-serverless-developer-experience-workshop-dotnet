# Variables
STAGE ?= local
REGION ?= ap-southeast-2
TERRAFORM_STATE_BUCKET ?=
CONFIRM_ACCOUNT_GLOBAL ?=

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

include ../common.mk

init-api-gateway-account: TF_STATE_KEY := uni-prop-$(REGION)-shared-api-gateway-account.tfstate
init-api-gateway-account: ## Initialize for the account-level API Gateway logging configuration
	$(call tf_init,api-gateway-account,$(TERRAFORM_DIR_API_GATEWAY_ACCOUNT))

init-namespaces: TF_STATE_KEY := uni-prop-shared-namespaces.tfstate
init-namespaces: ## Initialize for namespaces
	$(call tf_init,namespaces,$(TERRAFORM_DIR_NAMESPACES))

init-images-local: TF_STATE_KEY := uni-prop-local-shared-images.tfstate
init-images-local: ## Initialize for local images
	$(call tf_init,images-local,$(TERRAFORM_DIR_IMAGES))

init-images-dev: TF_STATE_KEY := uni-prop-dev-shared-images.tfstate
init-images-dev: ## Initialize for dev images
	$(call tf_init,images-dev,$(TERRAFORM_DIR_IMAGES))

init-images-prod: TF_STATE_KEY := uni-prop-prod-shared-images.tfstate
init-images-prod: ## Initialize for prod images
	$(call tf_init,images-prod,$(TERRAFORM_DIR_IMAGES))

init: ensure-state-backend ## Initialize all shared components sequentially and leave images on local state
	+$(MAKE) init-api-gateway-account
	+$(MAKE) init-namespaces
	+$(MAKE) init-images-dev
	+$(MAKE) init-images-prod
	+$(MAKE) init-images-local

plan-api-gateway-account: TF_STAGE := shared
plan-api-gateway-account: TF_VARS := -var="region=$(REGION)"
plan-api-gateway-account: init-api-gateway-account ## Plan account-level API Gateway logging resources
	$(call tf_plan,$(TERRAFORM_DIR_API_GATEWAY_ACCOUNT))

plan-namespaces: TF_STAGE := shared
plan-namespaces: TF_VARS := -var="region=$(REGION)"
plan-namespaces: init-namespaces ## Plan global Unicorn Properties namespaces
	$(call tf_plan,$(TERRAFORM_DIR_NAMESPACES))

plan-images-local: TF_STAGE := local
plan-images-local: TF_VARS := -var="stage=local" -var="region=$(REGION)"
plan-images-local: init-images-local ## Plan shared images for local environment
	$(call tf_plan,$(TERRAFORM_DIR_IMAGES))

plan-images-dev: TF_STAGE := dev
plan-images-dev: TF_VARS := -var="stage=dev" -var="region=$(REGION)"
plan-images-dev: init-images-dev ## Plan shared images for dev environment
	$(call tf_plan,$(TERRAFORM_DIR_IMAGES))

plan-images-prod: TF_STAGE := prod
plan-images-prod: TF_VARS := -var="stage=prod" -var="region=$(REGION)"
plan-images-prod: init-images-prod ## Plan shared images for prod environment and save the plan
	$(call tf_plan,$(TERRAFORM_DIR_IMAGES))

plan-images: plan-images-local plan-images-dev plan-images-prod ## Plan shared images for all environments

plan: plan-api-gateway-account plan-namespaces plan-images ## Plan all shared infrastructure

deploy-api-gateway-account: TF_STAGE := shared
deploy-api-gateway-account: TF_VARS := -var="region=$(REGION)"
deploy-api-gateway-account: init-api-gateway-account ## Deploy account-level API Gateway logging resources
	@echo "Deploying account-level API Gateway logging resources..."
	$(call tf_apply,$(TERRAFORM_DIR_API_GATEWAY_ACCOUNT))

deploy-namespaces: TF_STAGE := shared
deploy-namespaces: TF_VARS := -var="region=$(REGION)"
deploy-namespaces: init-namespaces ## Deploy global Unicorn Properties namespaces
	@echo "Deploying global namespaces..."
	$(call tf_apply,$(TERRAFORM_DIR_NAMESPACES))

deploy-images-local: TF_STAGE := local
deploy-images-local: TF_VARS := -var="stage=local" -var="region=$(REGION)"
deploy-images-local: init-images-local ## Deploy shared images for local environment
	@echo "Deploying shared images stack for local environment..."
	$(call tf_apply,$(TERRAFORM_DIR_IMAGES))

deploy-images-dev: TF_STAGE := dev
deploy-images-dev: TF_VARS := -var="stage=dev" -var="region=$(REGION)"
deploy-images-dev: init-images-dev ## Deploy shared images for dev environment
	@echo "Deploying shared images stack for dev environment..."
	$(call tf_apply,$(TERRAFORM_DIR_IMAGES))

deploy-images-prod: TF_STAGE := prod
deploy-images-prod: TF_VARS := -var="stage=prod" -var="region=$(REGION)"
deploy-images-prod: init-images-prod ## Deploy the saved shared images plan for prod environment
	@echo "Deploying shared images stack for prod environment..."
	$(call tf_apply,$(TERRAFORM_DIR_IMAGES))

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

delete-namespaces: TF_STAGE := shared
delete-namespaces: TF_VARS := -var="region=$(REGION)"
delete-namespaces: init-namespaces ## Delete account-global namespaces (requires CONFIRM_ACCOUNT_GLOBAL=DESTROY)
	@if [ "$(CONFIRM_ACCOUNT_GLOBAL)" != "DESTROY" ]; then \
		echo "Account-global namespace deletion blocked. These SSM parameters are used by every stage. Set CONFIRM_ACCOUNT_GLOBAL=DESTROY after reviewing the impact." >&2; \
		exit 1; \
	fi
	@echo "Deleting global namespaces..."
	$(call tf_destroy,$(TERRAFORM_DIR_NAMESPACES))

delete-images-local: TF_STAGE := local
delete-images-local: TF_VARS := -var="stage=local" -var="region=$(REGION)"
delete-images-local: init-images-local ## Delete shared images for local environment
	@echo "Deleting shared images stack for local environment..."
	$(call tf_destroy,$(TERRAFORM_DIR_IMAGES))

delete-images-dev: TF_STAGE := dev
delete-images-dev: TF_VARS := -var="stage=dev" -var="region=$(REGION)"
delete-images-dev: init-images-dev ## Delete shared images for dev environment
	@echo "Deleting shared images stack for dev environment..."
	$(call tf_destroy,$(TERRAFORM_DIR_IMAGES))

delete-images-prod: TF_STAGE := prod
delete-images-prod: TF_VARS := -var="stage=prod" -var="region=$(REGION)"
delete-images-prod: init-images-prod ## Delete shared images for prod environment
	@echo "Deleting shared images stack for prod environment..."
	$(call tf_destroy,$(TERRAFORM_DIR_IMAGES))

delete-images: delete-images-prod delete-images-dev delete-images-local ## Delete all shared images stacks

delete: delete-images delete-namespaces ## Delete all shared infrastructure
