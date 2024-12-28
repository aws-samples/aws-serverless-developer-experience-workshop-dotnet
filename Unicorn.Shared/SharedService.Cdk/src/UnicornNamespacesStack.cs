using Amazon.CDK;
using Constructs;
using SharedService.Cdk.Constructs;

namespace SharedService.Cdk
{
    public class UnicornNamespacesStack : Stack
    {
        public UnicornNamespacesStack(Construct scope, string id, IStackProps props = null!) : base(scope, id, props)
        {
            var namespaces = new NamespacesConstruct(this, "Namespaces");
            
            // Namespace outputs
            new CfnOutput(this, "UnicornContractsNamespace", new CfnOutputProps
            {
                Description = "Unicorn Contracts namespace parameter",
                Value = namespaces.UnicornContractsNamespace.ParameterName
            });
            
            new CfnOutput(this, "UnicornPropertiesNamespace", new CfnOutputProps
            {
                Description = "Unicorn Properties namespace parameter",
                Value = namespaces.UnicornPropertiesNamespace.ParameterName
            });

            new CfnOutput(this, "UnicornWebNamespace", new CfnOutputProps
            {
                Description = "Unicorn Web namespace parameter",
                Value = namespaces.UnicornWebNamespace.ParameterName
            });

            new CfnOutput(this, "UnicornContractsNamespaceValue", new CfnOutputProps
            {
                Description = "Unicorn Contracts namespace parameter value",
                Value = namespaces.UnicornContractsNamespace.StringValue
            });

            new CfnOutput(this, "UnicornPropertiesNamespaceValue", new CfnOutputProps
            {
                Description = "Unicorn Properties namespace parameter value",
                Value = namespaces.UnicornPropertiesNamespace.StringValue
            });

            new CfnOutput(this, "UnicornWebNamespaceValue", new CfnOutputProps
            {
                Description = "Unicorn Web namespace parameter value",
                Value = namespaces.UnicornWebNamespace.StringValue
            });


        }
    }
} 