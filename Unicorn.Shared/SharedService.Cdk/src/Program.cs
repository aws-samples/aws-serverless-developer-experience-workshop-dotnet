using Amazon.CDK;

namespace SharedService.Cdk
{
    sealed class Program
    {
        public static void Main(string[] args)
        {
            var app = new App(); 
            
            new UnicornNamespacesStack(app, "uni-prop-namespaces", new StackProps
            {
                Description = "Global namespaces for Unicorn Properties applications and services. This only needs to be deployed once."
            });
            
            new UnicornImagesStack(app, "uni-prop-images", new StackProps
            {
                Description = "Global namespaces for Unicorn Properties applications and services. This only needs to be deployed once."
            });
            
            app.Synth();
        }
    }
} 