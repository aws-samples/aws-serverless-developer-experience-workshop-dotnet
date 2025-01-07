using Amazon.CDK;
using Amazon.CDK.AWS.DynamoDB;
using Amazon.CDK.AWS.Lambda;
using Amazon.CDK.AWS.Events;
using Amazon.CDK.AWS.Events.Targets;
using Amazon.CDK.AWS.SQS;
using Amazon.CDK.AWS.Logs;
using Amazon.CDK.AWS.SSM;
using Amazon.CDK.AWS.IAM;
using Amazon.CDK.AWS.APIGateway;
using Constructs;

namespace Unicorn.Web.Cdk
{
    public class WebStack : Stack
    {
        public WebStack(Construct scope, string id, IStackProps props = null) : base(scope, id, props)
        {
            var stage = new CfnParameter(this, "Stage", new CfnParameterProps
            {
                Type = "String",
                Default = "local",
                AllowedValues = new[] { "local", "dev", "prod" }
            });

            // DynamoDB Table
            var webTable = new Table(this, "WebTable", new TableProps
            {
                PartitionKey = new Attribute { Name = "PK", Type = AttributeType.STRING },
                SortKey = new Attribute { Name = "SK", Type = AttributeType.STRING },
                BillingMode = BillingMode.PAY_PER_REQUEST,
                RemovalPolicy = RemovalPolicy.DESTROY
            });

            // EventBus
            var eventBus = new EventBus(this, "UnicornWebEventBus", new EventBusProps
            {
                EventBusName = $"UnicornWebBus-{stage.ValueAsString}"
            });

            // SQS Queues
            var dlq = new Queue(this, "UnicornWebIngestDLQ", new QueueProps
            {
                QueueName = $"UnicornWebIngestDLQ-{stage.ValueAsString}",
                Encryption = QueueEncryption.SQS_MANAGED,
                RetentionPeriod = Duration.Days(14),
                RemovalPolicy = RemovalPolicy.DESTROY
            });

            var ingestQueue = new Queue(this, "UnicornWebIngestQueue", new QueueProps
            {
                QueueName = $"UnicornWebIngestQueue-{stage.ValueAsString}",
                Encryption = QueueEncryption.SQS_MANAGED,
                RetentionPeriod = Duration.Days(14),
                DeadLetterQueue = new DeadLetterQueue
                {
                    MaxReceiveCount = 1,
                    Queue = dlq
                },
                VisibilityTimeout = Duration.Seconds(20),
                RemovalPolicy = RemovalPolicy.DESTROY
            });

            // Lambda Functions
            var searchFunction = new Function(this, "SearchFunction", new FunctionProps
            {
                Runtime = Runtime.DOTNET_8,
                Handler = "Unicorn.Web.SearchService::Unicorn.Web.SearchService.PropertySearchFunction::FunctionHandler",
                Code = Code.FromAsset("../SearchService"),
                MemorySize = 512,
                Timeout = Duration.Seconds(10),
                Tracing = Tracing.ACTIVE,
                Architecture = Architecture.X86_64,
                Environment = new Dictionary<string, string>
                {
                    ["DYNAMODB_TABLE"] = webTable.TableName,
                    ["EVENT_BUS"] = eventBus.EventBusName,
                    // Add other environment variables...
                }
            });

            webTable.GrantReadData(searchFunction);

            // API Gateway
            var api = new RestApi(this, "UnicornWebApi", new RestApiProps
            {
                RestApiName = "Unicorn Web API",
                DeployOptions = new StageOptions
                {
                    StageName = stage.ValueAsString,
                    TracingEnabled = true,
                    MetricsEnabled = true,
                    LoggingLevel = MethodLoggingLevel.INFO
                }
            });

            // Continue with other resources...
            
            // SSM Parameters
            new StringParameter(this, "UnicornWebEventBusParam", new StringParameterProps
            {
                ParameterName = $"/uni-prop/{stage.ValueAsString}/UnicornWebEventBus",
                StringValue = eventBus.EventBusName
            });

            new StringParameter(this, "UnicornWebEventBusArnParam", new StringParameterProps
            {
                ParameterName = $"/uni-prop/{stage.ValueAsString}/UnicornWebEventBusArn",
                StringValue = eventBus.EventBusArn
            });

            // Outputs
            new CfnOutput(this, "ApiUrl", new CfnOutputProps
            {
                Value = api.Url,
                Description = "Web service API endpoint"
            });

            new CfnOutput(this, "WebTableName", new CfnOutputProps
            {
                Value = webTable.TableName,
                Description = "Name of the DynamoDB Table for Unicorn Web"
            });
        }
    }
} 