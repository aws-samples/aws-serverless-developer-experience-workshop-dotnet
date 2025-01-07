using System;
using System.Collections.Generic;
using Amazon.CDK;
using Amazon.CDK.AWS.APIGateway;
using Amazon.CDK.AWS.DynamoDB;
using Amazon.CDK.AWS.Events;
using Amazon.CDK.AWS.Events.Targets;
using Amazon.CDK.AWS.IAM;
using Amazon.CDK.AWS.Lambda;
using Amazon.CDK.AWS.Lambda.EventSources;
using Amazon.CDK.AWS.Logs;
using Amazon.CDK.AWS.Pipes;
using Amazon.CDK.AWS.SQS;
using Amazon.CDK.AWS.SSM;
using Constructs;
using AssetOptions = Amazon.CDK.AWS.S3.Assets.AssetOptions;
using Attribute = Amazon.CDK.AWS.DynamoDB.Attribute;
using EventBus = Amazon.CDK.AWS.Events.EventBus;
using EventBusProps = Amazon.CDK.AWS.Events.EventBusProps;
using LogGroupProps = Amazon.CDK.AWS.Logs.LogGroupProps;

namespace ContractService.Cdk
{
    // <summary>
    // CDK Stack that defines the infrastructure for the Unicorn Contracts Service.
    // This service handles contract management for properties through API Gateway,
    // SQS queues, Lambda functions, and DynamoDB storage.
    // </summary>
    public class ContractsServiceStack : Stack
    {
        internal ContractsServiceStack(Construct scope, string id, ContractsServiceStackProps props) : base(scope, id,
            props)
        {
            var stage = props.Stage;
            var ns = props.ServiceNamespace;

            #region EventBridge

            // <summary>
            // Creates an EventBridge event bus for the Contracts Service.
            // This bus is used to publish and consume contract-related events,
            // enabling event-driven communication between service components.
            // </summary>
            var unicornContractsEventBus = new EventBus(this, "UnicornContractsEventBus", new EventBusProps
            {
                EventBusName = $"UnicornContractsBus-{stage}"
            });

            // <summary>
            // Configures the event bus policy to only allow events from this service's namespace.
            // This ensures proper access control and event isolation.
            // </summary>
            new CfnEventBusPolicy(this, "ContractEventsBusPublishPolicy", new CfnEventBusPolicyProps()
            {
                EventBusName = unicornContractsEventBus.EventBusName,
                StatementId = $"OnlyContactsServiceCanPublishToEventBus-{stage}",
                Statement = new PolicyStatement(new PolicyStatementProps
                {
                    Effect = Effect.ALLOW,
                    Principals = new[] { new AccountPrincipal(Stack.Of(this).Account) },
                    Actions = new[] { "events:PutEvents" },
                    Resources = new[] { unicornContractsEventBus.EventBusArn },
                    Conditions = new Dictionary<string, object>
                    {
                        {
                            "StringEquals",
                            new Dictionary<string, string>
                            {
                                { "events:source", ns }
                            }
                        }
                    }
                }).ToStatementJson()
            });

            var cloudWatchLogGroupName = $"/aws/events/${stage}/${ns}-catchall";
            var cloudWatchLogGroup = new LogGroup(this, "UnicornContractsEventBusLogGroup", new LogGroupProps
            {
                Retention = SetRetentionForStage(stage),
                RemovalPolicy = RemovalPolicy.DESTROY
            });

            // Create EventBridge Rule
            var eventRule = new Rule(this, "contracts.catchall", new RuleProps
            {
                EventBus = unicornContractsEventBus,
                Description = "Catch all events for the contracts service",
                EventPattern = new EventPattern
                {
                    Account = [Account],
                    Source = [ns]
                },
                Targets =
                [
                    new CloudWatchLogGroup(cloudWatchLogGroup)
                ]
            });

            // Share Event bus name through SSM
            var paramBusName = $"/uni-prop/{stage}/UnicornContractsEventBus";
            new StringParameter(this, "UnicornContractsEventBusNameParam", new StringParameterProps
            {
                ParameterName = paramBusName,
                StringValue = unicornContractsEventBus.EventBusName,
                Description = "Namespace for the Unicorn Contracts domain",
                SimpleName = false
            });

            // Share Event bus ARN through SSM
            var paramBusArn = $"/uni-prop/{stage}/UnicornContractsEventBusArn";
            new StringParameter(this, "UnicornContractsEventBusArnParam", new StringParameterProps
            {
                ParameterName = paramBusArn,
                StringValue = unicornContractsEventBus.EventBusArn,
                Description = "Namespace for the Unicorn Contracts domain",
                SimpleName = false
            });

            #endregion

            #region SQS injestion

            // <summary>
            // Dead Letter Queue (DLQ) for the contract ingestion queue.
            // Messages that fail processing after 1 attempt are moved here for investigation.
            // Messages are retained for 14 days (1,209,600 seconds).
            // </summary>
            var ingestDeadLetterQueue = new DeadLetterQueue
            {
                MaxReceiveCount = 1,
                Queue = new Queue(this, "UnicornContractsIngestQueueDlq", new QueueProps
                {
                    RetentionPeriod = Duration.Seconds(1209600),
                    Encryption = QueueEncryption.SQS_MANAGED,
                })
            };


            // Main ingestion queue for processing contract events.
            var ingestQueue = new Queue(this, "UnicornContractsIngestQueue", new QueueProps
            {
                RetentionPeriod = Duration.Seconds(1209600),
                Encryption = QueueEncryption.SQS_MANAGED,
                VisibilityTimeout = Duration.Seconds(20),
                DeadLetterQueue = ingestDeadLetterQueue
            });

            #endregion

            #region DynamoDB

            // DynamoDB table for storing contract information.
            var contractsTable = new Table(this, $"ContractsTable-{stage}", new TableProps
            {
                PartitionKey = new Attribute { Name = "PropertyId", Type = AttributeType.STRING },
                BillingMode = BillingMode.PAY_PER_REQUEST,
                Stream = StreamViewType.NEW_AND_OLD_IMAGES,
                RemovalPolicy = RemovalPolicy.DESTROY, // Be careful with this in production
            });

            #endregion

            #region Lambda functions

            // <summary>
            // Contract event handler Lambda function.
            // Processes messages from the ingestion queue and:
            // - Stores contract data in DynamoDB
            // - Publishes events to EventBridge
            // - Implements proper error handling and logging
            // 
            // Environment variables configure:
            // - AWS Lambda Powertools for .NET
            // - Service namespace
            // - Logging levels and sampling
            // </summary>
            // Bundling options for Lambda function
            var buildOptions = new BundlingOptions
            {
                Image = Runtime.DOTNET_8.BundlingImage,
                User = "root",
                OutputType = BundlingOutput.ARCHIVED,
                Command = new[]
                {
                    "/bin/sh",
                    "-c",
                    " dotnet tool install -g Amazon.Lambda.Tools" +
                    " && dotnet build" +
                    " && dotnet lambda package --output-package /asset-output/function.zip"
                }
            };

            var contractFunction = new Function(this, "ContractEventHandlerFunction", new FunctionProps
            {
                Runtime = Runtime.DOTNET_8,
                Code = Code.FromAsset("../ContractsService/", new AssetOptions
                {
                    Bundling = buildOptions,
                }),
                Handler =
                    "Unicorn.Contracts.ContractService::Unicorn.Contracts.ContractService.ContractEventHandler::FunctionHandler",
                Architecture = Architecture.X86_64,
                Tracing = Tracing.ACTIVE,
                LogGroup = new LogGroup(this, "ContractEventHandlerFunctionLogGroup", new LogGroupProps
                {
                    Retention = RetentionDays
                        .THREE_DAYS, // todo: need to change this so it is dependent on a environment.
                }),
                Environment = new Dictionary<string, string>
                {
                    { "DYNAMODB_TABLE", " !Ref ContractsTable" },
                    { "SERVICE_NAMESPACE", ns },
                    { "POWERTOOLS_LOGGER_CASE", "PascalCase" },
                    { "POWERTOOLS_SERVICE_NAME", ns },
                    { "POWERTOOLS_TRACE_DISABLED", "false" },
                    { "POWERTOOLS_LOGGER_LOG_EVENT", (stage == "dev").ToString() },
                    { "POWERTOOLS_LOGGER_SAMPLE_RATE", stage == "dev" ? "0.1" : "0" },
                    { "POWERTOOLS_METRICS_NAMESPACE", ns },
                    { "POWERTOOLS_LOG_LEVEL", "INFO" },
                    { "LOG_LEVEL", "INFO" },
                }
            });

            // Add the SQS queue as an event source
            contractFunction.AddEventSource(new SqsEventSource(ingestQueue));
            ingestQueue.GrantConsumeMessages(contractFunction);

            #endregion

            #region API Gateway

            var apiLogGroup = new LogGroup(this, "UnicornContractsApiLogGroup", new LogGroupProps
            {
                Retention = SetRetentionForStage(
                    stage) // RetentionDays.THREE_DAYS // todo: need to change this so it is dependent on a environment.
            });


            // <summary>
            // REST API Gateway for the Contracts Service.
            // Features:
            // - Regional endpoint
            // - Request validation
            // - Access logging to CloudWatch
            // - Request throttling (10 RPS, burst 100)
            // - X-Ray tracing enabled
            // - Metrics enabled
            // </summary>
            //Proxy all request from the root path "/" to Lambda Function One
            var restApi = new RestApi(this, "ContractsServiceApi", new RestApiProps
            {
                Description = "Unicorn Properties Contract Service API",
                EndpointConfiguration = new EndpointConfiguration
                {
                    Types = new[] { EndpointType.REGIONAL }
                },
                DeployOptions = new StageOptions
                {
                    AccessLogDestination = new LogGroupLogDestination(apiLogGroup),
                    AccessLogFormat = AccessLogFormat.JsonWithStandardFields(new JsonWithStandardFieldProps
                    {
                        Caller = false,
                        HttpMethod = true,
                        Ip = true,
                        Protocol = true,
                        RequestTime = true,
                        ResourcePath = true,
                        ResponseLength = true,
                        Status = true,
                        User = true
                    }),
                    MethodOptions = new Dictionary<string, IMethodDeploymentOptions>
                    {
                        {
                            "/*/*", new MethodDeploymentOptions
                            {
                                // This special path applies to all resource paths and all HTTP methods
                                ThrottlingRateLimit = 10,
                                ThrottlingBurstLimit = 100
                            }
                        }
                    },
                    TracingEnabled = true,
                    MetricsEnabled = true
                }
            });


            // JSON Schema validation model for contract creation requests.
            var createContractModel = restApi.AddModel("CreateContractModel", new ModelOptions
            {
                ContentType = "application/json",
                ModelName = "CreateContractModel",
                Schema = new JsonSchema
                {
                    Schema = JsonSchemaVersion.DRAFT4,
                    Type = JsonSchemaType.OBJECT,
                    Required = new[] { "property_id", "seller_name", "address" },
                    Properties = new Dictionary<string, IJsonSchema>
                    {
                        { "property_id", new JsonSchema { Type = JsonSchemaType.STRING } },
                        { "seller_name", new JsonSchema { Type = JsonSchemaType.STRING } },
                        {
                            "address", new JsonSchema
                            {
                                Type = JsonSchemaType.OBJECT,
                                Required = new[] { "city", "country", "number", "street" },
                                Properties = new Dictionary<string, IJsonSchema>()
                                {
                                    { "city", new JsonSchema { Type = JsonSchemaType.STRING } },
                                    { "country", new JsonSchema { Type = JsonSchemaType.STRING } },
                                    { "number", new JsonSchema { Type = JsonSchemaType.STRING } },
                                    { "street", new JsonSchema { Type = JsonSchemaType.STRING } }
                                }
                            }
                        }
                    }
                }
            });

            // Request validator for the create contract model
            var createContractValidator = new RequestValidator(this, "CreateContractValidator",
                new RequestValidatorProps
                {
                    RestApi = restApi,
                    ValidateRequestBody = true
                });

            // Update contract model
            var updateContractModel = restApi.AddModel("UpdateContractModel", new ModelOptions
            {
                ContentType = "application/json",
                ModelName = "UpdateContractModel",
                Schema = new JsonSchema
                {
                    Schema = JsonSchemaVersion.DRAFT4,
                    Type = JsonSchemaType.OBJECT,
                    Required = new[] { "property_id" },
                    Properties = new Dictionary<string, IJsonSchema>
                    {
                        { "property_id", new JsonSchema { Type = JsonSchemaType.STRING } }
                    }
                }
            });

            // Request validator for the update contract model
            var updateContractValidator = new RequestValidator(this, "UpdateContractValidator",
                new RequestValidatorProps
                {
                    RestApi = restApi,
                    ValidateRequestBody = true
                });

            // API Gateway role to integrate with ingest queue
            var restApiIntegrationRole = new Role(this, "UnicornContractsApiIntegrationRole", new RoleProps
            {
                AssumedBy = new ServicePrincipal("apigateway.amazonaws.com")
            });

            // Grant send messages permission to the ingest queue
            ingestQueue.GrantSendMessages(restApiIntegrationRole);

            // Add contracts resource to the root resource
            var apiContractsResource = restApi.Root.AddResource("contracts", new ResourceOptions
            {
                DefaultIntegration = new AwsIntegration(new AwsIntegrationProps
                {
                    Service = "sqs",
                    IntegrationHttpMethod = "POST",
                    Path = ingestQueue.QueueArn,
                    Options = new IntegrationOptions
                    {
                        CredentialsRole = restApiIntegrationRole,
                        RequestTemplates = new Dictionary<string, string>
                        {
                            {
                                "application/json",
                                "Action=SendMessage&MessageBody=$input.body&MessageAttribute.1.Name=HttpMethod&MessageAttribute.1.Value.StringValue=$context.httpMethod&MessageAttribute.1.Value.DataType=String"
                            }
                        },
                        RequestParameters = new Dictionary<string, string>
                        {
                            {
                                "integration.request.header.Content-Type", "'application/x-www-form-urlencoded'"
                            }
                        }
                    }
                })
            });

            // Add POST method to /contracts with validation
            apiContractsResource.AddMethod("POST", null, options: new MethodOptions
            {
                RequestValidator = createContractValidator,
                RequestModels = new Dictionary<string, IModel>
                {
                    { "application/json", createContractModel }
                }
            });

            // Add PUT method to /contracts with validation
            apiContractsResource.AddMethod("PUT", null, options: new MethodOptions
            {
                RequestValidator = updateContractValidator,
                RequestModels = new Dictionary<string, IModel>
                {
                    { "application/json", updateContractModel }
                }
            });

            #endregion

            #region EventBridge Pipe

            // Create DLQ for the pipe
            var dlq = new Queue(this, "ContractsTableStreamToEventPipeDLQ", new QueueProps
            {
                QueueName = $"ContractsTableStreamToEventPipeDLQ-{stage}",
                Encryption = QueueEncryption.SQS_MANAGED,
                RetentionPeriod = Duration.Days(14),
                RemovalPolicy = RemovalPolicy.DESTROY
            });

            // Create Log Group for the pipe
            var logGroup = new LogGroup(this, "ContractsPipeLogGroup",
                new LogGroupProps
                {
                    Retention = RetentionDays.THREE_DAYS,
                    RemovalPolicy = RemovalPolicy.DESTROY
                });

            //   Create IAM Role for the pipe
            var pipeRole = new Role(this, "ContractsTableStreamToEventPipeRole", new RoleProps
            {
                RoleName = $"ContractsTableStreamToEventPipeRole-{stage}",
                Description = "IAM Role for the Pipe",
                AssumedBy = new ServicePrincipal("pipes.amazonaws.com"),
            });

            // Add necessary permissions to the role
            pipeRole.AddToPolicy(new PolicyStatement(new PolicyStatementProps
            {
                Effect = Effect.ALLOW,
                Actions = ["dynamodb:ListStreams"],
                Resources = ["*"]
            }));

            // Create the Pipe
            new CfnPipe(this, "ContractsTableStreamToEventPipe", new CfnPipeProps
            {
                RoleArn = pipeRole.RoleArn,
                Source = contractsTable.TableStreamArn ??
                         throw new InvalidOperationException("Table Stream Arn is not defined."),
                Target = unicornContractsEventBus.EventBusArn,
                SourceParameters = new CfnPipe.PipeSourceParametersProperty
                {
                    DynamoDbStreamParameters = new CfnPipe.PipeSourceDynamoDBStreamParametersProperty
                    {
                        StartingPosition = "LATEST",
                        BatchSize = 1,
                        MaximumRetryAttempts = 3,
                        DeadLetterConfig = new CfnPipe.DeadLetterConfigProperty
                        {
                            Arn = dlq.QueueArn
                        }
                    },
                    FilterCriteria = new CfnPipe.FilterCriteriaProperty
                    {
                        Filters = new[]
                        {
                            new CfnPipe.FilterProperty
                            {
                                Pattern =
                                    "{\"eventName\":[\"INSERT\",\"MODIFY\"]," +
                                    "\"dynamodb\":{\"NewImage\":" +
                                    "{\"ContractStatus\":{\"S\":[\"DRAFT\",\"APPROVED\"]}}}}"
                            }
                        }
                    }
                },
                TargetParameters = new CfnPipe.PipeTargetParametersProperty
                {
                    EventBridgeEventBusParameters = new CfnPipe.PipeTargetEventBridgeEventBusParametersProperty
                    {
                        DetailType = "ContractStatusChanged",
                        Source = ns
                    },
                    InputTemplate =
                        "{\n  \"PropertyId\": \"<$.dynamodb.Keys.PropertyId.S>\",\n  " +
                        "\"ContractId\": \"<$.dynamodb.NewImage.ContractId.S>\",\n  " +
                        "\"ContractStatus\": \"<$.dynamodb.NewImage.ContractStatus.S>\",\n  " +
                        "\"ContractLastModifiedOn\": \"<$.dynamodb.NewImage.ContractLastModifiedOn.S>\"\n}"
                }
            });

            #endregion

            #region Outputs

            // SQS OUTPUTS
            new CfnOutput(this, "IngestQueueUrl", new CfnOutputProps
            {
                Description = "URL for the Ingest SQS Queue",
                Value = ingestQueue.QueueUrl
            });

            // DYNAMODB OUTPUTS
            new CfnOutput(this, "ContractsTableName", new CfnOutputProps
            {
                Description = "DynamoDB table storing contract information",
                Value = contractsTable.TableName
            });

            //LAMBDA FUNCTIONS OUTPUTS
            new CfnOutput(this, "ContractEventHandlerFunctionName", new CfnOutputProps
            {
                Description = "ContractEventHandler function name",
                Value = contractFunction.FunctionName
            });

            new CfnOutput(this, "ContractEventHandlerFunctionArn", new CfnOutputProps
            {
                Description = "ContractEventHandler function ARN",
                Value = contractFunction.FunctionArn
            });

            // EVENT BRIDGE OUTPUTS 
            new CfnOutput(this, "UnicornContractsEventBusName", new CfnOutputProps
            {
                Description = "Event bus name",
                Value = unicornContractsEventBus.EventBusName
            });

            // CLOUDWATCH LOGS OUTPUTS
            // new CfnOutput(this, "UnicornContractsCatchAllLogGroupArn", new CfnOutputProps()
            // {
            //     Description = "Log all events on the service's EventBridge Bus",
            //     Value = unicornContractsCatchAll.LogGroupArn
            // });

            #endregion
        }

        // <summary>
        // Determines the CloudWatch log retention period based on environment stage.
        // - local/dev: 3 days
        // - prod: 1 month
        // - default: 3 days
        // </summary>
        private RetentionDays SetRetentionForStage(string stage)
        {
            switch (stage)
            {
                case "local":
                    return RetentionDays.THREE_DAYS;
                case "dev":
                    return RetentionDays.THREE_DAYS;
                case "prod":
                    return RetentionDays.ONE_MONTH;
                default:
                    return RetentionDays.THREE_DAYS;
            }
        }
    }
}