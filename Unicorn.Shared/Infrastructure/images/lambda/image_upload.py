import os
import zipfile
from urllib.request import urlopen
import boto3
import json

zip_file_name = "property_images.zip"
url = f"https://ws-assets-prod-iad-r-iad-ed304a55c2ca1aee.s3.us-east-1.amazonaws.com/9a27e484-7336-4ed0-8f90-f2747e4ac65c/{zip_file_name}"
temp_zip_download_location = f"/tmp/{zip_file_name}"

s3 = boto3.resource('s3')

def create(event, context):
  image_bucket_name = event.get('ResourceProperties', {}).get('DestinationBucket', event.get('DestinationBucket'))
  if not image_bucket_name:
    raise ValueError("DestinationBucket not found in event")
  
  bucket = s3.Bucket(image_bucket_name)
  print(f"downloading zip file from: {url} to: {temp_zip_download_location}")
  r = urlopen(url).read()
  with open(temp_zip_download_location, 'wb') as t:
    t.write(r)
    print('zip file downloaded')

  print(f"unzipping file: {temp_zip_download_location}")
  with zipfile.ZipFile(temp_zip_download_location,'r') as zip_ref:
    zip_ref.extractall('/tmp')
  
  print('file unzipped')
  
  #### upload to s3
  for root,_,files in os.walk('/tmp/property_images'):
    for file in files:
      print(f"file: {os.path.join(root, file)}")
      print(f"s3 bucket: {image_bucket_name}")
      bucket.upload_file(os.path.join(root, file), f"property_images/{file}")

def delete(event, context):
  image_bucket_name = event.get('ResourceProperties', {}).get('DestinationBucket', event.get('DestinationBucket'))
  if not image_bucket_name:
    return
  
  img_bucket = s3.Bucket(image_bucket_name)
  img_bucket.objects.delete()
  img_bucket.delete()

def lambda_handler(event, context):
  try:
    request_type = event.get('RequestType', 'Create')
    if request_type in ['Create', 'Update']:
      create(event, context)
    elif request_type == 'Delete':
      delete(event, context)
    return {
      'statusCode': 200,
      'body': json.dumps('Success')
    }
  except Exception as e:
    print(f"Error: {str(e)}")
    raise








