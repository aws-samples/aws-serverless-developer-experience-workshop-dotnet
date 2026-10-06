STAGE ?=
CONFIRM_ACCOUNT_GLOBAL ?=

NAMESPACE_MAKE = $(MAKE) -o ensure-state-backend STAGE="$(STAGE)"

.PHONY: help validate-stage confirm-account-global-destroy deploy-all delete-all

help: ## Show full-system deployment commands
	@echo "Unicorn Properties Terraform orchestration"
	@echo ""
	@echo "Usage: make deploy-all STAGE=local|dev|prod"
	@echo "       make delete-all STAGE=local|dev|prod CONFIRM_ACCOUNT_GLOBAL=DESTROY"

validate-stage:
	@case "$(STAGE)" in \
		local|dev|prod) ;; \
		*) echo "STAGE must be one of: local, dev, prod." >&2; exit 1 ;; \
	esac

confirm-account-global-destroy:
	@if [ "$(CONFIRM_ACCOUNT_GLOBAL)" != "DESTROY" ]; then \
		echo "Account-global namespace deletion blocked. This removes shared SSM parameters used by every stage. Set CONFIRM_ACCOUNT_GLOBAL=DESTROY after reviewing the impact." >&2; \
		exit 1; \
	fi

deploy-all: validate-stage ## Deploy all Terraform roots in dependency order
	@echo "Phase 1/5: Ensure the shared Terraform state backend exists"
	+$(MAKE) -C Unicorn.Shared ensure-state-backend STAGE="$(STAGE)"
	@echo "Phase 2/5: Deploy shared account, namespaces, and $(STAGE) images"
	+$(NAMESPACE_MAKE) -C Unicorn.Shared deploy-api-gateway-account
	+$(NAMESPACE_MAKE) -C Unicorn.Shared deploy-namespaces
	+$(NAMESPACE_MAKE) -C Unicorn.Shared deploy-images-$(STAGE)
	@echo "Phase 3/5: Deploy service domains"
	+$(NAMESPACE_MAKE) -C Unicorn.Contracts deploy-domain
	+$(NAMESPACE_MAKE) -C Unicorn.Approvals deploy-domain
	+$(NAMESPACE_MAKE) -C Unicorn.Web deploy-domain
	@echo "Phase 4/5: Deploy schemas and services"
	+$(NAMESPACE_MAKE) -C Unicorn.Contracts deploy-schema
	+$(NAMESPACE_MAKE) -C Unicorn.Approvals deploy-schema
	+$(NAMESPACE_MAKE) -C Unicorn.Web deploy-schema
	+$(NAMESPACE_MAKE) -C Unicorn.Contracts deploy-service
	+$(NAMESPACE_MAKE) -C Unicorn.Approvals deploy-service
	+$(NAMESPACE_MAKE) -C Unicorn.Web deploy-service
	@echo "Phase 5/5: Deploy subscriptions"
	+$(NAMESPACE_MAKE) -C Unicorn.Approvals deploy-contracts-subscriptions
	+$(NAMESPACE_MAKE) -C Unicorn.Approvals deploy-web-subscriptions
	+$(NAMESPACE_MAKE) -C Unicorn.Web deploy-subscriptions

delete-all: validate-stage confirm-account-global-destroy ## Destroy stage roots and account-global namespaces in reverse dependency order
	@echo "Reverse phase 5/5: Delete subscriptions"
	+$(NAMESPACE_MAKE) -C Unicorn.Web delete-subscriptions
	+$(NAMESPACE_MAKE) -C Unicorn.Approvals delete-web-subscriptions
	+$(NAMESPACE_MAKE) -C Unicorn.Approvals delete-contracts-subscriptions
	@echo "Reverse phase 4/5: Delete services and schemas"
	+$(NAMESPACE_MAKE) -C Unicorn.Web delete-service
	+$(NAMESPACE_MAKE) -C Unicorn.Approvals delete-service
	+$(NAMESPACE_MAKE) -C Unicorn.Contracts delete-service
	+$(NAMESPACE_MAKE) -C Unicorn.Web delete-schema
	+$(NAMESPACE_MAKE) -C Unicorn.Approvals delete-schema
	+$(NAMESPACE_MAKE) -C Unicorn.Contracts delete-schema
	@echo "Reverse phase 3/5: Delete service domains"
	+$(NAMESPACE_MAKE) -C Unicorn.Web delete-domain
	+$(NAMESPACE_MAKE) -C Unicorn.Approvals delete-domain
	+$(NAMESPACE_MAKE) -C Unicorn.Contracts delete-domain
	@echo "Reverse phase 2/5: Delete $(STAGE) images and shared namespaces"
	+$(NAMESPACE_MAKE) -C Unicorn.Shared delete-images-$(STAGE)
	+$(NAMESPACE_MAKE) -C Unicorn.Shared delete-namespaces CONFIRM_ACCOUNT_GLOBAL="$(CONFIRM_ACCOUNT_GLOBAL)"
	@echo "The account-global namespaces were deleted. The Shared api-gateway-account singleton and state backend were preserved."
