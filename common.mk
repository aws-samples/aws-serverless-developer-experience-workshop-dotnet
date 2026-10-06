# Shared Terraform backend and lifecycle helpers for namespace Makefiles.

CONFIRM_PROD ?=
AWS_ACCOUNT_ID := $(shell aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
TF_STAGE ?= $(STAGE)
TF_VARS ?= -var="stage=$(STAGE)" -var="region=$(REGION)"
COMMON_MK_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
PLAN_MANIFEST_SCRIPT := $(COMMON_MK_DIR)scripts/terraform_plan_manifest.py

terraform_state_key = $(if $(TF_STATE_KEY),$(TF_STATE_KEY),uni-prop-$(STAGE)-$(TERRAFORM_NAMESPACE)-$(1).tfstate)

.PHONY: check-aws-account-id ensure-state-backend

check-aws-account-id:
ifeq ($(strip $(AWS_ACCOUNT_ID)),)
	@echo "AWS credentials unavailable: unable to determine AWS account ID." >&2
	@exit 1
else
	@:
endif

ensure-state-backend: check-aws-account-id ## Ensure the S3 state backend exists
	@set -eu; \
	if [ -z "$(TERRAFORM_STATE_BUCKET)" ]; then \
		BUCKET_NAME="uni-prop-terraform-state-$(AWS_ACCOUNT_ID)-$(REGION)"; \
	else \
		BUCKET_NAME="$(TERRAFORM_STATE_BUCKET)"; \
	fi; \
	echo "Checking state bucket: $$BUCKET_NAME"; \
	if ! aws s3api head-bucket --bucket "$$BUCKET_NAME" --region $(REGION) >/dev/null 2>&1; then \
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
	fi; \
	aws s3api put-public-access-block \
		--bucket "$$BUCKET_NAME" \
		--public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true \
		--region $(REGION); \
	aws s3api put-bucket-encryption \
		--bucket "$$BUCKET_NAME" \
		--server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}' \
		--region $(REGION); \
	aws s3api put-bucket-versioning \
		--bucket "$$BUCKET_NAME" \
		--versioning-configuration Status=Enabled \
		--region $(REGION); \
	echo "State bucket hardened: $$BUCKET_NAME"

define tf_init
	@echo "Initializing for $(1)..."
	@if [ -z "$(strip $(AWS_ACCOUNT_ID))" ]; then \
		echo "AWS credentials unavailable: unable to determine AWS account ID." >&2; \
		exit 1; \
	fi; \
	if [ -z "$(TERRAFORM_STATE_BUCKET)" ]; then \
		BUCKET_NAME="uni-prop-terraform-state-$(AWS_ACCOUNT_ID)-$(REGION)"; \
	else \
		BUCKET_NAME="$(TERRAFORM_STATE_BUCKET)"; \
	fi; \
	if ! aws s3api head-bucket --bucket "$$BUCKET_NAME" --region $(REGION) >/dev/null 2>&1; then \
		echo "State bucket not found. Run 'make ensure-state-backend' first."; \
		exit 1; \
	fi; \
	cd $(2) && terraform init \
		-reconfigure \
		-backend-config="bucket=$$BUCKET_NAME" \
		-backend-config="key=$(call terraform_state_key,$(1))" \
		-backend-config="region=$(REGION)" \
		-backend-config="use_lockfile=true"
endef

define tf_plan
	@if [ "$(TF_STAGE)" = "prod" ]; then \
		PLAN_PATH="$(abspath $(1))/.terraform/prod.tfplan"; \
		rm -f "$$PLAN_PATH.manifest.json"; \
		cd $(1) && terraform plan $(TF_VARS) -out=.terraform/prod.tfplan; \
		python3 "$(PLAN_MANIFEST_SCRIPT)" create \
			--repo-root "$(COMMON_MK_DIR)" \
			--terraform-root "$(abspath $(1))" \
			--plan "$$PLAN_PATH" \
			$(foreach manifest,$(2),--package-manifest "$(abspath $(manifest))"); \
	else \
		cd $(1) && terraform plan $(TF_VARS); \
	fi
endef

define tf_apply
	@if [ "$(TF_STAGE)" = "prod" ]; then \
		if [ "$(CONFIRM_PROD)" != "APPLY" ]; then \
			echo "Production apply blocked. Run the prod plan first, review it, then set CONFIRM_PROD=APPLY."; \
			exit 1; \
		fi; \
		if [ ! -f "$(1)/.terraform/prod.tfplan" ]; then \
			echo "Production apply blocked: $(1)/.terraform/prod.tfplan does not exist."; \
			exit 1; \
		fi; \
		python3 "$(PLAN_MANIFEST_SCRIPT)" verify \
			--repo-root "$(COMMON_MK_DIR)" \
			--terraform-root "$(abspath $(1))" \
			--plan "$(abspath $(1))/.terraform/prod.tfplan" \
			$(foreach manifest,$(2),--package-manifest "$(abspath $(manifest))"); \
		cd $(1) && terraform apply .terraform/prod.tfplan; \
	else \
		cd $(1) && terraform apply $(TF_VARS) -auto-approve; \
	fi
endef

define tf_destroy
	@if [ "$(TF_STAGE)" = "prod" ] && [ "$(CONFIRM_PROD)" != "DESTROY" ]; then \
		echo "Production destroy blocked. Review the impact, then set CONFIRM_PROD=DESTROY."; \
		exit 1; \
	fi; \
	cd $(1) && terraform destroy $(TF_VARS) -auto-approve
endef
