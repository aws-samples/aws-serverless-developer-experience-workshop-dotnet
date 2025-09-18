# SAM Templates Documentation

This directory contains AWS SAM (Serverless Application Model) templates for the Unicorn Contracts Service, part of the AWS Serverless Developer Experience workshop. The templates are organized to separate domain-level resources from service-specific resources.

## Template Overview

### 1. `domain.yaml` - Domain Resources Template

**Purpose**: Creates shared domain-level infrastructure that can be used by multiple services within the Unicorn Contracts domain.

**Key Resources**:

- **EventBridge Event Bus** (`UnicornContractsEventBus`): Central event bus for contract-related events
- **SSM Parameters**: Store event bus name, ARN, and schema registry information for cross-service access
- **Event Bus Logging**: Complete logging setup with delivery sources, destinations, and delivery configurations
- **Schema Registry** (`UnicornContractsSchemaRegistry`): Event schema management for contract events
- **Event Bus Policies**: Access control for creating rules and publishing events

**Notable Features**:

- Configurable logging levels based on stage (INFO for dev/local, ERROR for prod)
- Proper deletion policies for all logging resources to ensure clean stack deletion
- Cross-service event bus policy restricting rule creation to specific sources

Note: This template provides the foundation for event-driven integrations for all Unicorn Contract services. It needs to be deployed before any other services.

### 2. `contracts-registry/contract-status-changed-schema.yaml` - Event Schema Template

**Purpose**: Defines the event schema for `ContractStatusChanged` events in the EventBridge Schema Registry.

**Key Resources**:

- **ContractStatusChangedEventSchema** (`AWS::EventSchemas::Schema`): OpenAPI 3.0 schema definition for contract status change events

**Schema Structure**:

- **Event Source**: Retrieved from SSM parameter (unicorn-contracts namespace)
- **Detail Type**: `ContractStatusChanged`
- **Required Fields**:
  - `contract_id`: Unique identifier for the contract
  - `contract_status`: Current status of the contract
  - `property_id`: Associated property identifier
  - `contract_last_modified_by`: User who made the change
  - `contract_last_modified_on`: Timestamp of the change (ISO 8601 format)

**Integration**:

- Uses SSM parameter resolution to get the schema registry name from domain template
- Follows AWS EventBridge event envelope structure
- Enables code generation for strongly-typed event handling

### 3. `contracts-service.yaml` - Service Resources Template

**Purpose**: Deploys the complete Unicorn Contracts Service with all its components.

**Key Resources**:

#### Lambda Functions

- **ContractEventHandlerFunction**: Processes contract requests from SQS queue
  - Runtime: .NET 8
  - Memory: 512MB, Timeout: 15s
  - Integrated with AWS Powertools for observability

#### API Gateway

- **UnicornContractsApi**: REST API with regional endpoint
- **API Gateway Integration Role**: Allows API Gateway to send messages to SQS
- **CloudWatch Logging**: Comprehensive access logging and account configuration

#### Data Storage

- **ContractsTable**: DynamoDB table with PropertyId as partition key
- **DynamoDB Streams**: Enabled for change data capture
- **Pay-per-request billing** for cost optimization

#### Message Processing

- **UnicornContractsIngestQueue**: Main SQS queue for API requests
- **UnicornContractsIngestDLQ**: Dead letter queue for failed messages
- **EventBridge Pipes**: Transforms DynamoDB stream events to EventBridge events

#### Event Processing

- **Event Bus Policies**: Publishing restrictions to domain namespace
- **Catchall Rule**: Development rule to log all events (should be disabled in production)
- **EventBridge Pipes**: Converts DynamoDB changes to `ContractStatusChanged` events

#### Observability

- **CloudWatch Log Groups**: Separate log groups for Lambda, API Gateway, and EventBridge
- **AWS X-Ray Tracing**: Enabled for distributed tracing
- **Powertools Integration**: Structured logging, metrics, and tracing

## Template Parameters

All templates accept a `Stage` parameter with allowed values:

- `local`: Development environment (3-day log retention)
- `dev`: Development environment (3-day log retention)
- `prod`: Production environment (14-day log retention, reduced logging)

## Deployment Order

1. **Deploy Domain Resources First**:

   ```bash
   sam deploy \
   --template-file ./iac/domain.yaml \
   --stack-name uni-prop-local-contracts-domain \
   --parameter-overrides Stage=local \
   --capabilities CAPABILITY_IAM CAPABILITY_AUTO_EXPAND \
   --region ap-southeast-2 \
   --resolve-s3
   ```

2. **Deploy Event Schema** (For schema governance):

   ```bash

   sam deploy \
      --template-file ./iac/schema-registry/ContractStatusChanged-schema.yaml \
      --stack-name uni-prop-local-contracts-contract-status-changed-schema \
      --parameter-overrides Stage=local \
      --capabilities CAPABILITY_IAM \
      --region ap-southeast-2 \
      --resolve-s3

   ```

3. **Deploy Service Resources**:

   ```bash
      sam deploy \
      --template-file ./iac/contracts-service.yaml \
      --stack-name uni-prop-local-contracts-contracts-service \
      --parameter-overrides Stage=local \
      --capabilities CAPABILITY_IAM CAPABILITY_AUTO_EXPAND \
      --region ap-southeast-2 \
      --resolve-s3
   ```

## Key Configuration Details

### Environment Variables (Global)

- `DYNAMODB_TABLE`: Reference to ContractsTable
- `SERVICE_NAMESPACE`: Retrieved from SSM parameter
- `POWERTOOLS_*`: AWS Powertools configuration for observability

### Security

- IAM roles follow least privilege principle
- Event bus policies restrict cross-service access
- SQS queues use managed server-side encryption
- API Gateway has throttling configured (10 burst, 100 rate)

### Monitoring & Logging

- CloudWatch log retention varies by stage
- EventBridge logging captures both INFO and ERROR events
- API Gateway access logs in JSON format
- Lambda function logs with configurable levels

## Dependencies

### External Dependencies

- SSM Parameters: `/uni-prop/UnicornContractsNamespace`
- API Definition: `api.yaml` file (referenced via AWS::Include transform)

### Cross-Template Dependencies

- `contracts-service.yaml` depends on SSM parameters created by `domain.yaml`
- `contract-status-changed-schema.yaml` depends on schema registry created by `domain.yaml`
- Event bus ARN and schema registry name are shared via SSM parameters between templates

## Best Practices Implemented

1. **Infrastructure as Code**: All resources defined declaratively
2. **Environment Separation**: Stage-based configuration
3. **Security**: Least privilege IAM, encryption at rest
4. **Observability**: Comprehensive logging and tracing
5. **Resilience**: Dead letter queues, retry policies
6. **Cost Optimization**: Pay-per-request billing, appropriate timeouts
7. **Clean Deletion**: Proper deletion policies for stateful resources

## Troubleshooting

### Common Issues

1. **SSM Parameter Dependencies**: Ensure domain template is deployed first
2. **API Definition**: Verify `api.yaml` exists in the correct location
3. **Lambda Code**: Ensure ContractsService directory contains compiled code
4. **Permissions**: Verify IAM capabilities are included in deployment commands

### Monitoring

- Check CloudWatch logs for Lambda execution errors
- Monitor SQS dead letter queues for failed messages
- Use X-Ray traces for performance analysis
- Review EventBridge metrics for event processing

## Configuration Files

- `samconfig.toml`: Contains default deployment configuration
- `README.md`: Deployment instructions and commands
