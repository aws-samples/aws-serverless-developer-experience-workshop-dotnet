# Makefile for Unicorn Approvals Service Infrastructure

# Variables
STAGE ?= local
REGION ?= ap-southeast-2
STACK_PREFIX = uni-prop-$(STAGE)

.PHONY: help build deploy deploy-domain deploy-service deploy-schema deploy-subscriptions deploy-contracts-subscriptions deploy-web-subscriptions delete-contracts-subscriptions delete-web-subscriptions test lint clean delete

help: ## Show available commands
	@echo "Unicorn Approvals Service Infrastructure"
	@echo ""
	@echo "Usage: make [target] [STAGE=local|dev|prod] [REGION=ap-southeast-2]"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-15s %s\n", $$1, $$2}'

build: ## Build the application
	@echo "Building .NET application..."
	@dotnet restore ApprovalsService/ApprovalsService.csproj
	@dotnet restore ApprovalsService.Tests/ApprovalsService.Tests.csproj
	@dotnet build ApprovalsService/ApprovalsService.csproj
	@sam build --template-file Infrastructure/approvals-service.yaml

deploy-domain: ## Deploy domain resources (EventBridge, Schema Registry)
	@echo "Deploying domain resources..."
	@sam deploy \
		--template-file Infrastructure/domain.yaml \
		--stack-name $(STACK_PREFIX)-approvals-domain \
		--parameter-overrides Stage=$(STAGE) \
		--capabilities CAPABILITY_IAM CAPABILITY_AUTO_EXPAND \
		--region $(REGION) \
		--resolve-s3 \
		--no-confirm-changeset \
		--no-fail-on-empty-changeset

deploy-service: build ## Deploy service resources (Lambda, Step Functions, DynamoDB)
	@echo "Deploying service resources..."
	@sam deploy \
		--template-file Infrastructure/approvals-service.yaml \
		--stack-name $(STACK_PREFIX)-approvals-service \
		--parameter-overrides Stage=$(STAGE) \
		--capabilities CAPABILITY_IAM CAPABILITY_AUTO_EXPAND \
		--region $(REGION) \
		--resolve-s3 \
		--no-confirm-changeset \
		--no-fail-on-empty-changeset

deploy-schema: ## Deploy event schema
	@echo "Deploying event schema..."
	@sam deploy \
		--template-file Infrastructure/schema-registry/PublicationEvaluationCompleted-schema.yaml \
		--stack-name $(STACK_PREFIX)-approvals-schema-PublicationEvaluationCompleted \
		--parameter-overrides Stage=$(STAGE) \
		--capabilities CAPABILITY_IAM \
		--region $(REGION) \
		--resolve-s3 \
		--no-confirm-changeset \
		--no-fail-on-empty-changeset

deploy-subscriptions: deploy-contracts-subscriptions deploy-web-subscriptions ## Deploy event subscriptions

deploy-contracts-subscriptions: ## Deploy contracts event subscriptions
	@echo "Deploying contracts subscriptions..."
	@sam deploy \
		--template-file Infrastructure/subscriptions/unicorn-contracts-subscriptions.yaml \
		--stack-name $(STACK_PREFIX)-approvals-contracts-subscriptions \
		--parameter-overrides Stage=$(STAGE) \
		--capabilities CAPABILITY_IAM \
		--region $(REGION) \
		--resolve-s3 \
		--no-confirm-changeset \
		--no-fail-on-empty-changeset

deploy-web-subscriptions: ## Deploy web event subscriptions
	@echo "Deploying web subscriptions..."
	@sam deploy \
		--template-file Infrastructure/subscriptions/unicorn-web-subscriptions.yaml \
		--stack-name $(STACK_PREFIX)-approvals-web-subscriptions \
		--parameter-overrides Stage=$(STAGE) \
		--capabilities CAPABILITY_IAM \
		--region $(REGION) \
		--resolve-s3 \
		--no-confirm-changeset \
		--no-fail-on-empty-changeset

delete-contracts-subscriptions: ## Deploy contracts event subscriptions
	@echo "Deleting contracts subscriptions..."
	@aws cloudformation delete-stack --stack-name $(STACK_PREFIX)-approvals-contracts-subscriptions --region $(REGION) || true
	@echo "Waiting for subscription stack to be deleted..."
	@aws cloudformation wait stack-delete-complete --stack-name $(STACK_PREFIX)-approvals-contracts-subscriptions --region $(REGION) || true
	@echo "Done"

delete-web-subscriptions: ## Deploy web event subscriptions
	@echo "Deleting web subscriptions..."
	@aws cloudformation delete-stack --stack-name $(STACK_PREFIX)-approvals-web-subscriptions --region $(REGION) || true
	@echo "Waiting for subscription stack to be deleted..."
	@aws cloudformation wait stack-delete-complete --stack-name $(STACK_PREFIX)-approvals-web-subscriptions --region $(REGION) || true
	@echo "Done"

deploy: deploy-domain deploy-service deploy-schema deploy-contracts-subscriptions ## Deploy all infrastructure and application

test: ## Run tests
	@echo "Running tests..."
	@dotnet test ApprovalsService.Tests/ApprovalsService.Tests.csproj

lint: ## Lint CloudFormation templates
	@echo "Linting CloudFormation templates..."
	@cfn-lint Infrastructure/approvals-service.yaml -a cfn_lint_serverless.rules
	@cfn-lint Infrastructure/domain.yaml
	@cfn-lint Infrastructure/schema-registry/PublicationEvaluationCompleted-schema.yaml
	@cfn-lint Infrastructure/subscriptions/unicorn-contracts-subscriptions.yaml
	@cfn-lint Infrastructure/subscriptions/unicorn-web-subscriptions.yaml

clean: ## Clean build artifacts
	@echo "Cleaning build artifacts..."
	@rm -rf .aws-sam/
	@dotnet clean

delete: ## Delete all stacks
	@echo "Deleting stacks in reverse order..."
	@aws cloudformation delete-stack --stack-name $(STACK_PREFIX)-approvals-web-subscriptions --region $(REGION) || true
	@aws cloudformation delete-stack --stack-name $(STACK_PREFIX)-approvals-contracts-subscriptions --region $(REGION) || true
	@echo "Waiting for subscription stacks to be deleted..."
	@aws cloudformation wait stack-delete-complete --stack-name $(STACK_PREFIX)-approvals-web-subscriptions --region $(REGION) || true
	@aws cloudformation wait stack-delete-complete --stack-name $(STACK_PREFIX)-approvals-contracts-subscriptions --region $(REGION) || true
	@aws cloudformation delete-stack --stack-name $(STACK_PREFIX)-approvals-schema-PublicationEvaluationCompleted --region $(REGION) || true
	@aws cloudformation delete-stack --stack-name $(STACK_PREFIX)-approvals-service --region $(REGION) || true
	@echo "Waiting for schema and service stacks to be deleted..."
	@aws cloudformation wait stack-delete-complete --stack-name $(STACK_PREFIX)-approvals-schema-PublicationEvaluationCompleted --region $(REGION) || true
	@aws cloudformation wait stack-delete-complete --stack-name $(STACK_PREFIX)-approvals-service --region $(REGION) || true
	@aws cloudformation delete-stack --stack-name $(STACK_PREFIX)-approvals-domain --region $(REGION) || true
	@echo "All stacks deleted"