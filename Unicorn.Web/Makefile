# Makefile for Unicorn Web Service Infrastructure

# Variables
STAGE ?= local
REGION ?= ap-southeast-2
STACK_PREFIX = uni-prop-$(STAGE)

.PHONY: help build deploy deploy-domain deploy-schema deploy-subscriptions deploy-service test lint format clean delete ci

help: ## Show available commands
	@echo "Unicorn Web Service Infrastructure"
	@echo ""
	@echo "Usage: make [target] [STAGE=local|dev|prod] [REGION=ap-southeast-2]"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-15s %s\n", $$1, $$2}'

build: ## Build the application
	@echo "Building .NET application..."
	@dotnet restore PublicationManagerService/PublicationManagerService.csproj
	@dotnet restore SearchService/SearchService.csproj
	@dotnet build PublicationManagerService/PublicationManagerService.csproj
	@dotnet build SearchService/SearchService.csproj
	@sam build --template-file Infrastructure/web-service/template.yaml

deploy-domain: ## Deploy domain resources (EventBridge, Schema Registry)
	@echo "Deploying domain resources..."
	@sam deploy \
		--template-file Infrastructure/domain.yaml \
		--stack-name $(STACK_PREFIX)-web-domain \
		--parameter-overrides Stage=$(STAGE) \
		--capabilities CAPABILITY_IAM CAPABILITY_AUTO_EXPAND \
		--region $(REGION) \
		--resolve-s3 \
		--no-confirm-changeset \
		--no-fail-on-empty-changeset

deploy-schema: ## Deploy event schema
	@echo "Deploying event schema..."
	@sam deploy \
		--template-file Infrastructure/schema-registry/PublicationApprovalRequested-schema.yaml \
		--stack-name $(STACK_PREFIX)-web-schema-PublicationApprovalRequested \
		--parameter-overrides Stage=$(STAGE) \
		--region $(REGION) \
		--resolve-s3 \
		--no-confirm-changeset \
		--no-fail-on-empty-changeset

deploy-subscriptions: ## Deploy event subscriptions
	@echo "Deploying event subscriptions..."
	@sam deploy \
		--template-file Infrastructure/subscriptions/unicorn-approvals-subscriptions.yaml \
		--stack-name $(STACK_PREFIX)-web-subscriptions-approvals \
		--parameter-overrides Stage=$(STAGE) \
		--region $(REGION) \
		--resolve-s3 \
		--no-confirm-changeset \
		--no-fail-on-empty-changeset

deploy-service: build ## Deploy web service
	@echo "Deploying web service..."
	@sam deploy \
		--stack-name $(STACK_PREFIX)-web-service \
		--parameter-overrides Stage=$(STAGE) \
		--capabilities CAPABILITY_IAM CAPABILITY_AUTO_EXPAND \
		--region $(REGION) \
		--resolve-s3 \
		--no-confirm-changeset \
		--no-fail-on-empty-changeset

deploy: deploy-domain deploy-schema deploy-subscriptions deploy-service ## Deploy all infrastructure and application

test: ## Run tests
	@echo "Running tests..."
	@dotnet test PublicationManagerService.Tests/PublicationManagerService.Tests.csproj
	@dotnet test SearchService.Tests/SearchService.Tests.csproj

lint: ## Lint CloudFormation templates
	@echo "Linting CloudFormation templates..."
	@cfn-lint Infrastructure/web-service/template.yaml -a cfn_lint_serverless.rules
	@cfn-lint Infrastructure/domain.yaml
	@cfn-lint Infrastructure/schema-registry/PublicationApprovalRequested-schema.yaml
	@cfn-lint Infrastructure/subscriptions/unicorn-approvals-subscriptions.yaml

format: ## Format C# code (dotnet format)
	@echo "Formatting C# code..."
	@dotnet format Common/Common.csproj
	@dotnet format PublicationManagerService/PublicationManagerService.csproj
	@dotnet format PublicationManagerService.Tests/PublicationManagerService.Tests.csproj
	@dotnet format SearchService/SearchService.csproj
	@dotnet format SearchService.Tests/SearchService.Tests.csproj

# The AWS SDK clients need a region even in unit tests; credentials are never needed.
ci: export AWS_REGION ?= $(REGION)
ci: export AWS_DEFAULT_REGION ?= $(REGION)
ci: lint build test ## Run the same checks as CI (lint, build, test); needs no AWS credentials

clean: ## Clean build artifacts
	@echo "Cleaning build artifacts..."
	@rm -rf .aws-sam/
	@dotnet clean

delete: ## Delete all stacks
	@echo "Deleting stacks in reverse order..."
	@aws cloudformation delete-stack --stack-name $(STACK_PREFIX)-web-service --region $(REGION) || true
	@aws cloudformation delete-stack --stack-name $(STACK_PREFIX)-web-subscriptions-approvals --region $(REGION) || true
	@aws cloudformation delete-stack --stack-name $(STACK_PREFIX)-web-schema-PublicationApprovalRequested --region $(REGION) || true
	@echo "Waiting for service, subscriptions, and schema stacks to be deleted..."
	@aws cloudformation wait stack-delete-complete --stack-name $(STACK_PREFIX)-web-service --region $(REGION) || true
	@aws cloudformation wait stack-delete-complete --stack-name $(STACK_PREFIX)-web-subscriptions-approvals --region $(REGION) || true
	@aws cloudformation wait stack-delete-complete --stack-name $(STACK_PREFIX)-web-schema-PublicationApprovalRequested --region $(REGION) || true
	@aws cloudformation delete-stack --stack-name $(STACK_PREFIX)-web-domain --region $(REGION) || true
	@echo "Waiting for domain stack to be deleted..."
	@aws cloudformation wait stack-delete-complete --stack-name $(STACK_PREFIX)-web-domain --region $(REGION) || true
	@echo "All stacks deleted"