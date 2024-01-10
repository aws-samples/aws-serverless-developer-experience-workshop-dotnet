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

namespace ContractService.Cdk;

public class ContractsServiceStackGlobals : Stack
{
    internal ContractsServiceStackGlobals(Construct scope, string id, StackProps props) : base(scope, id, props)
    {
        // Create a new SSM parameter for Unicorn Contracts EventBus Arn
        var serviceNamespaceParam = new StringParameter(this, "UnicornContractsNamespaceParam",
            new StringParameterProps
            {
                Description = $"Global namespace for the Unicorn Contracts applications",
                StringValue = "unicorn.contracts",
                ParameterName = $"/uni-prop/UnicornContractsNamespace",
                SimpleName = false
            });
    }
}