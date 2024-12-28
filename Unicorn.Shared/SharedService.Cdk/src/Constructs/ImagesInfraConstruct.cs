using Amazon.CDK;
using Amazon.CDK.AWS.S3;
using Amazon.CDK.AWS.SSM;
using Amazon.CDK.AWS.Lambda;
using Amazon.CDK.AWS.Logs;
using Amazon.CDK.CustomResources;
using Constructs;

namespace SharedService.Cdk.Constructs
{
    public class ImagesInfraConstruct : Construct
    {
        public Bucket ImagesBucket { get; }
        public IStringParameter ImagesBucketParameter { get; }

        public ImagesInfraConstruct(Construct scope, string id, string stage) : base(scope, id)
        {
            // Create S3 Bucket
            ImagesBucket = new Bucket(this, "UnicornPropertiesImagesBucket", new BucketProps
            {
                BucketName = $"uni-prop-{stage}-images-{Stack.Of(this).Account}-{Stack.Of(this).Region}",
                RemovalPolicy = RemovalPolicy.DESTROY,
                AutoDeleteObjects = true
            });

            // Create SSM Parameter
            ImagesBucketParameter = new StringParameter(this, "UnicornPropertiesImagesBucketParam", new StringParameterProps
            {
                ParameterName = $"/uni-prop/{stage}/ImagesBucket",
                StringValue = ImagesBucket.BucketName, 
                Description = "Images bucket for {stage} environment.", 
                SimpleName = false
            });

            // Create Image Upload Lambda Function
            var imageUploadFunction = new Function(this, "ImageUploadFunction", new FunctionProps
            {
                Runtime = Runtime.PYTHON_3_11,
                Handler = "index.lambda_handler",
                Architecture = Architecture.ARM_64,
                Timeout = Duration.Seconds(15),
                MemorySize = 512,
                Code = Code.FromInline(@"
import os
import zipfile
from urllib.request import urlopen
import boto3
import cfnresponse

zip_file_name = ""property_images.zip""
url = f""https://ws-assets-prod-iad-r-iad-ed304a55c2ca1aee.s3.us-east-1.amazonaws.com/9a27e484-7336-4ed0-8f90-f2747e4ac65c/{zip_file_name}""
temp_zip_download_location = f""/tmp/{zip_file_name}""

s3 = boto3.resource('s3')

def create(event, context):
    image_bucket_name = event['ResourceProperties']['DestinationBucket']
    bucket = s3.Bucket(image_bucket_name)
    print(f""downloading zip file from: {url} to: {temp_zip_download_location}"")
    r = urlopen(url).read()
    with open(temp_zip_download_location, 'wb') as t:
        t.write(r)
        print('zip file downloaded')

    print(f""unzipping file: {temp_zip_download_location}"")
    with zipfile.ZipFile(temp_zip_download_location,'r') as zip_ref:
        zip_ref.extractall('/tmp')
    
    print('file unzipped')
    
    #### upload to s3
    for root,_,files in os.walk('/tmp/property_images'):
        for file in files:
            print(f""file: {os.path.join(root, file)}"")
            print(f""s3 bucket: {image_bucket_name}"")
            bucket.upload_file(os.path.join(root, file), file)

def delete(event, context):
    image_bucket_name = event['ResourceProperties']['DestinationBucket']
    img_bucket = s3.Bucket(image_bucket_name)
    img_bucket.objects.delete()
    img_bucket.delete()

def lambda_handler(event, context):
    try:
        if event['RequestType'] in ['Create', 'Update']:
            create(event, context)
        elif event['RequestType'] in ['Delete']:
            delete(event, context)
    except Exception as e:
        print(e)
    cfnresponse.send(event, context, cfnresponse.SUCCESS, dict())
"),
                Tracing = Tracing.ACTIVE
            });

            // Grant S3 permissions to Lambda
            ImagesBucket.GrantReadWrite(imageUploadFunction);
            imageUploadFunction.AddToRolePolicy(new Amazon.CDK.AWS.IAM.PolicyStatement(new Amazon.CDK.AWS.IAM.PolicyStatementProps
            {
                Effect = Amazon.CDK.AWS.IAM.Effect.ALLOW,
                Actions = new[] { "s3:DeleteBucket" },
                Resources = new[] { ImagesBucket.BucketArn }
            }));

            // Create Log Group for Lambda
            new LogGroup(this, "ImageUploadFunctionLogGroup", new LogGroupProps
            {
                LogGroupName = $"/aws/lambda/{imageUploadFunction.FunctionName}",
                RemovalPolicy = RemovalPolicy.DESTROY
            });

            // Create Custom Resource
            new CustomResource(this, "ImageUpload", new CustomResourceProps
            {
                ServiceToken = imageUploadFunction.FunctionArn,
                Properties = new Dictionary<string, object>
                {
                    { "DestinationBucket", ImagesBucket.BucketName }
                }
            });
        }
    }
} 