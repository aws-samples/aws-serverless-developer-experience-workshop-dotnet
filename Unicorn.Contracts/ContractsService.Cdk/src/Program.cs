using System;
using System.Collections.Generic;
using Amazon.CDK;
using Amazon.CDK.AWS.SSM;
using Environment = Amazon.CDK.Environment;

namespace ContractService.Cdk;

public class ContractsServiceStackProps : StackProps
{
    public required string Stage { get; init; }
    public string ServiceNamespace { get; set; } = "";
}

sealed class Program
{
    public static void Main(string[] args)
    {
        var app = new App();
        var stage = app.Node.TryGetContext("stage")?.ToString() ?? "local";

        // Get environment configuration from default AWS profile
        var env = new Environment
        {
            Account = System.Environment.GetEnvironmentVariable("CDK_DEFAULT_ACCOUNT"),
            Region = System.Environment.GetEnvironmentVariable("CDK_DEFAULT_REGION")
        };

        var lookupStack = new Stack(app, "ParameterLookupStack", new StackProps { Env = env });
        var ns = StringParameter.ValueFromLookup(lookupStack, $"/uni-prop/UnicornContractsNamespace");

        new ContractsServiceStack(app, $"uni-prop-{stage}-contracts", new ContractsServiceStackProps
        {
           Stage = stage, 
            ServiceNamespace = ns,
            Env = env,
            Tags = new Dictionary<string, string>
            {
                { "stage", stage },
                { "project", "AWS Serverless Developer Experience" },
                { "namespace", ns }
            }
        });

        app.Synth();
    }
}