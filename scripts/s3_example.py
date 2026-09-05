import os
import boto3

BUCKET_NAME = os.environ["S3_BUCKET_NAME"]

s3 = boto3.client("s3", region_name="eu-west-1")

# Upload
s3.put_object(
    Bucket=BUCKET_NAME,
    Key="greetings/hello.json",
    Body='{"message": "hello from Python"}',
    ContentType="application/json",
)
print("Uploaded greetings/hello.json")

# List
response = s3.list_objects_v2(Bucket=BUCKET_NAME, Prefix="greetings/")
for obj in response.get("Contents", []):
    print(obj["Key"])

# Download
response = s3.get_object(Bucket=BUCKET_NAME, Key="greetings/hello.json")
content = response["Body"].read().decode("utf-8")
print(f"Downloaded: {content}")
