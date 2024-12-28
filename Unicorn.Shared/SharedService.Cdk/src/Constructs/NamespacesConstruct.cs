using Amazon.CDK;
using Amazon.CDK.AWS.SSM;
using Constructs;

namespace SharedService.Cdk.Constructs
{
    public class NamespacesConstruct : Construct
    {
        public IStringParameter UnicornContractsNamespace { get; }
        public IStringParameter UnicornPropertiesNamespace { get; }
        public IStringParameter UnicornWebNamespace { get; }

        public NamespacesConstruct(Construct scope, string id) : base(scope, id)
        {
            UnicornContractsNamespace = new StringParameter(this, "UnicornContractsNamespaceParam", new StringParameterProps
            {
                ParameterName = "/uni-prop/UnicornContractsNamespace",
                StringValue = "unicorn.contracts", 
                Description = "Namespace for the Unicorn Contracts domain", 
                SimpleName = false
            });
            
            UnicornPropertiesNamespace = new StringParameter(this, "UnicornPropertiesNamespaceParam", new StringParameterProps
            {
                ParameterName = "/uni-prop/UnicornPropertiesNamespace",
                StringValue = "unicorn.properties", 
                Description = "Namespace for the Unicorn Properties domain", 
                SimpleName = false
            });

            UnicornWebNamespace = new StringParameter(this, "UnicornWebNamespaceParam", new StringParameterProps
            {
                ParameterName = "/uni-prop/UnicornWebNamespace",
                StringValue = "unicorn.web", 
                Description = "Namespace for the Unicorn Web domain", 
                SimpleName = false
            });
        }
    }
} 