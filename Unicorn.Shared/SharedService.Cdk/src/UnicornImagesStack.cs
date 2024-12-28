using Amazon.CDK;
using Constructs;
using SharedService.Cdk.Constructs;

namespace SharedService.Cdk
{
    public class UnicornImagesStack : Stack
    {
        private readonly string[] _stages = new[] { "local", "dev", "prod" };
        public UnicornImagesStack(Construct scope, string id, IStackProps props = null!) : base(scope, id, props)
        {
            foreach (var stage in _stages)
            {
                var imagesInfra = new ImagesInfraConstruct(this, $"ImagesInfra-{stage}", stage);
                
                // Images infrastructure output
                new CfnOutput(this, $"ImageUploadBucketName-{stage}", new CfnOutputProps
                {
                    Description = $"S3 bucket for property images ({stage})",
                    Value = imagesInfra.ImagesBucket.BucketName
                });
            }
        }
    }
} 