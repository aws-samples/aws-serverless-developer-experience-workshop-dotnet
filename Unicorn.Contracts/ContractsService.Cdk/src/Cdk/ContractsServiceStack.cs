using System;
using System.Collections.Generic;
using System.Diagnostics;
using Amazon.CDK;
using Amazon.CDK.AWS.APIGateway;
using Amazon.CDK.AWS.DynamoDB;
using Amazon.CDK.AWS.IAM;
using Amazon.CDK.AWS.Lambda;
using Amazon.CDK.AWS.Lambda.EventSources;
using Amazon.CDK.AWS.Logs;
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
    public class ContractsServiceStack : Stack
    {
        internal ContractsServiceStack(Construct scope, string id, ContractsServiceStackProps props) : base(scope, id, props)
        {
             var ns = StringParameter.FromStringParameterAttributes(
                 this, "UnicornContractsNamespace", new StringParameterAttributes
                 {
                     ParameterName = $"/uni-prop/UnicornContractsNamespace"
                 }).StringValue;

            #region EventBridge

            // Event bus for Unicorn Contract Service used to publish and consume events
            var unicornContractsEventBus = new EventBus(this, "UnicornContractsEventBus", new EventBusProps
            {
                EventBusName = $"UnicornContractsBus-{props.Stage}"
            });

            var unicornContractsCatchAllLogGroup = new LogGroup(this,"UnicornContractsCatchAllLogGroup", new LogGroupProps
            {
                LogGroupName = $"/aws/events/${props.Stage}/${ns}-catchall",
                Retention = SetRetentionForStage(props.Stage),
            });

            // Event bus policy statement to restrict who can publish events (should only be services from UnicornContractsNamespace)
            // var eventBusPublisherPolicyStatement = new PolicyStatement(new PolicyStatementProps()
            // {
            //     Principals = new IPrincipal[] { new AccountPrincipal(Account)  }, // todo: resolve after fix https://github.com/aws/aws-cdk/issues/24031
            //     Actions = new[] { "events:PutEvents" },
            //     Resources = new[]
            //     {
            //         unicornContractsEventBus.EventBusArn
            //     },
            //     Conditions = new Dictionary<string, object>()
            //     {
            //         // Restrict to only services from UnicornContractsNamespace
            //         {
            //             "StringEquals",
            //             new Dictionary<string, string>()
            //                 { { "events:source", contractsNamespace.StringValue } }
            //         }
            //     }
            // });

            // EventBridge policy to allow specific principals to send events to the event bus.
            // new EventBusPolicy(this, "ContractEventsBusPublishPolicy", new EventBusPolicyProps()
            // {
            //     EventBus = unicornContractsEventBus,
            //     StatementId = $"OnlyContactsServiceCanPublishToEventBus-${props.Stage}",
            //     Statement = eventBusPublisherPolicyStatement
            // });

            #endregion

            # region SSM Parameters

            // Create a new SSM parameter for Unicorn Contracts EventBus name
            var unicornContractsEventBusNameParam = new StringParameter(this,
                "UnicornContractsEventBusNameParam", new StringParameterProps
                {
                    Description = $"Name of the Unicorn Contracts EventBus for {props.Stage} environment",
                    StringValue = unicornContractsEventBus.EventBusName,
                    ParameterName = $"/uni-prop/{props.Stage}/UnicornContractsEventBus",
                    SimpleName = false
                });

            // Create a new SSM parameter for Unicorn Contracts EventBus Arn
            var unicornContractsEventBusArnParam = new StringParameter(this, "UnicornContractsEventBusArnParam",
                new StringParameterProps
                {
                    Description = $"ARN of the Unicorn Contracts EventBus for {props.Stage} environment",
                    StringValue = unicornContractsEventBus.EventBusArn,
                    ParameterName = $"/uni-prop/{props.Stage}/UnicornContractsEventBusArn",
                    SimpleName = false
                });

            #endregion
            
            var ingestDeadLetterQueue = new DeadLetterQueue
            {
                MaxReceiveCount = 1,
                Queue = new Queue(this, "UnicornContractsIngestQueueDlq", new QueueProps
                {
                    RetentionPeriod = Duration.Seconds(1209600),
                    Encryption = QueueEncryption.SQS_MANAGED,
                })
            };

            // Create Ingest SQS queue with DLQ
            var ingestQueue = new Queue(this, "UnicornContractsIngestQueue", new QueueProps
            {
                RetentionPeriod = Duration.Seconds(1209600),
                Encryption = QueueEncryption.SQS_MANAGED,
                VisibilityTimeout = Duration.Seconds(20),
                DeadLetterQueue = ingestDeadLetterQueue
            });

            #region DynamoDB

            var contractsTable = new Table(this, "ContractsTable", new TableProps
            {
                PartitionKey = new Attribute { Name = "PropertyId", Type = AttributeType.STRING },
                BillingMode = BillingMode.PAY_PER_REQUEST,
                Stream = StreamViewType.NEW_AND_OLD_IMAGES
            });

            #endregion

            #region Lambda functions

            // Bundling options for Lambda function
            var buildOptions = new BundlingOptions
            {
                Image = Runtime.DOTNET_6.BundlingImage,
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

            // Contract event handler function pulls messages from Ingest queue
            var contractFunction = new Function(this, "ContractEventHandlerFunction", new FunctionProps
            {
                Runtime = Runtime.DOTNET_6,
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
                    { "SERVICE_NAMESPACE", $"/uni-prop/{props.Stage}/UnicornContractsNamespace" },
                    { "POWERTOOLS_LOGGER_CASE", "PascalCase" },
                    { "POWERTOOLS_SERVICE_NAME", $"/uni-prop/{props.Stage}/UnicornContractsNamespace" },
                    { "POWERTOOLS_TRACE_DISABLED", "false" },
                    { "POWERTOOLS_LOGGER_LOG_EVENT", (props.Stage == "dev").ToString() },
                    { "POWERTOOLS_LOGGER_SAMPLE_RATE", props.Stage == "dev" ? "0.1" : "0" },
                    { "POWERTOOLS_METRICS_NAMESPACE", $"/uni-prop/{props.Stage}/UnicornContractsNamespace" },
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
                Retention = SetRetentionForStage(props.Stage) // RetentionDays.THREE_DAYS // todo: need to change this so it is dependent on a environment.
            });


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

            // var responseModel = restApi.AddModel("CreateContractModel", new ModelOptions
            // {
            //     ContentType = "application/json",
            //     ModelName = "ResponseModel",
            //     Schema = new JsonSchema
            //     {
            //         Schema = JsonSchemaVersion.DRAFT4,
            //         Type = JsonSchemaType.OBJECT,
            //         Properties = new Dictionary<string, IJsonSchema>
            //         {
            //             { "property_id", new JsonSchema { Type = JsonSchemaType.STRING, Required = new[] { "true" } } },
            //             { "seller_name", new JsonSchema { Type = JsonSchemaType.STRING, Required = new[] { "true" } } },
            //             {
            //                 "address", new JsonSchema
            //                 {
            //                     Type = JsonSchemaType.OBJECT, Properties = new Dictionary<string, IJsonSchema>()
            //                     {
            //                         { "city", new JsonSchema { Type = JsonSchemaType.STRING, Required = new[] { "true" } } },
            //                         { "country", new JsonSchema { Type = JsonSchemaType.STRING, Required = new[] { "true" } } },
            //                         { "number", new JsonSchema { Type = JsonSchemaType.STRING, Required = new[] { "true" } } },
            //                         { "street", new JsonSchema { Type = JsonSchemaType.STRING, Required = new[] { "true" } } },
            //                     }
            //                 }
            //             }
            //         }
            //     }
            // });
            //
            // var updateModel = restApi.AddModel("UpdateContractModel", new ModelOptions
            // {
            //     ContentType = "application/json",
            //     ModelName = "ResponseModel",
            //     Schema = new JsonSchema
            //     {
            //         Schema = JsonSchemaVersion.DRAFT4,
            //         Type = JsonSchemaType.OBJECT,
            //         Properties = new Dictionary<string, IJsonSchema>ı
            //         {
            //             { "property_id", new JsonSchema { Type = JsonSchemaType.STRING, Required = new[] { "true" } } },
            //         }
            //     }
            // });

            // API Gateway deployment
            // new Deployment(this, "Deployment", new DeploymentProps { Api = restApi });


            // API Gateway role to integrate with ingest queue
            var restApiIntegrationRole = new Role(this, "UnicornContractsApiIntegrationRole", new RoleProps
            {
                AssumedBy = new ServicePrincipal("apigateway.amazonaws.com")
            });

            ingestQueue.GrantSendMessages(restApiIntegrationRole);

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

            apiContractsResource.AddMethod("POST");

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

        public ContractsServiceStack(string ns)
        {
            var ns1 = ns;
        }

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