using System.Collections.Generic;
using System.Diagnostics;
using Amazon.CDK;
using Amazon.CDK.AWS.Batch;
using Amazon.CDK.AWS.SSM;

namespace ContractService.Cdk;

public class ContractsServiceStackProps : StackProps
{
    public string Stage { get; init; }
    public string ServiceNamespace { get; init; } = "unicorn.contracts";
}

sealed class Program
{
    private const string AwsServerlessDeveloperExperience = "AWS Serverless Developer Experience";
    private const string ServiceNamespace = "unicorn.contracts";

    public static void Main(string[] args)
    {
        var app = new App();

        // The Globals stack needs to be deployed before any others. It contains resources that are gloablly 
        var globalStack = new ContractsServiceStackGlobals(app, "ContractsServiceStackGlobals", new StackProps
        {
            StackName = "uni-prop-local-contracts-globals"
        });


        var localStack = new ContractsServiceStack(app, "ContractsServiceStackLocal", new ContractsServiceStackProps
        {
            StackName = "uni-prop-local-contracts-cdk",
            Stage = "local",
            Tags = new Dictionary<string, string>
            {
                { "stage", "local" },
                { "project", AwsServerlessDeveloperExperience },
                { "namespace", ServiceNamespace }
            }
        });

        var devStack = new ContractsServiceStack(app, "ContractsServiceStackDev", new ContractsServiceStackProps
        {
            StackName = "uni-prop-dev-contracts-cdk",
            Stage = "dev",
            Tags = new Dictionary<string, string>
            {
                { "stage", "dev" },
                { "project", AwsServerlessDeveloperExperience }
            }
        });

        var prodStack = new ContractsServiceStack(app, "ContractsServiceStackProd", new ContractsServiceStackProps
        {
            StackName = "uni-prop-prop-contracts-cdk",
            Stage = "prod",
            Tags = new Dictionary<string, string>
            {
                { "stage", "prod" },
                { "project", AwsServerlessDeveloperExperience }
            }
        });

        app.Synth();
    }
}