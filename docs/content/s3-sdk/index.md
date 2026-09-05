# S3 from Code

You've provisioned a bucket with Terraform and uploaded objects via the CLI. Now let's do the same
from application code. The AWS SDK is available for many languages — below are the two most common
in the Axxes context: Java and Python.

Both use the
[Default Credential Provider Chain](https://docs.aws.amazon.com/sdk-for-java/latest/developer-guide/credentials-chain.html),
so they pick up your SSO session automatically — no credentials in code or config.

!!! note "Make sure your SSO session is active"
    Run `aws sso login --profile traineeship` before running any code that talks to AWS.

---

## Dependencies

=== "Java"

    Add the following to your `pom.xml` (use the AWS SDK BOM to manage versions):

    ```
    software.amazon.awssdk:s3
    ```

    If you're using the synchronous client you also need an HTTP implementation. The managed
    `url-connection-client` is the simplest option for non-Quarkus projects:

    ```
    software.amazon.awssdk:url-connection-client
    ```

=== "Python"

    ```shell
    pip install boto3
    ```

---

## Create a client

=== "Java"

    ```java
    S3Client s3 = S3Client.builder()
            .region(Region.EU_WEST_1)
            .build();
    ```

=== "Python"

    ```python
    import boto3

    s3 = boto3.client('s3', region_name='eu-west-1')
    ```

---

## Upload an object

=== "Java"

    ```java
    s3.putObject(
            PutObjectRequest.builder()
                    .bucket("your-bucket-name")
                    .key("greetings/hello.json")
                    .contentType("application/json")
                    .build(),
            RequestBody.fromString("{\"message\": \"hello from Java\"}"));
    ```

=== "Python"

    ```python
    s3.put_object(
        Bucket='your-bucket-name',
        Key='greetings/hello.json',
        Body='{"message": "hello from Python"}',
        ContentType='application/json'
    )
    ```

---

## List objects

=== "Java"

    ```java
    ListObjectsV2Response response = s3.listObjectsV2(
            ListObjectsV2Request.builder()
                    .bucket("your-bucket-name")
                    .prefix("greetings/")
                    .build());

    response.contents().forEach(obj -> System.out.println(obj.key()));
    ```

=== "Python"

    ```python
    response = s3.list_objects_v2(Bucket='your-bucket-name', Prefix='greetings/')

    for obj in response.get('Contents', []):
        print(obj['Key'])
    ```

---

## Download an object

=== "Java"

    ```java
    ResponseBytes<GetObjectResponse> bytes = s3.getObjectAsBytes(
            GetObjectRequest.builder()
                    .bucket("your-bucket-name")
                    .key("greetings/hello.json")
                    .build());

    System.out.println(bytes.asUtf8String());
    ```

=== "Python"

    ```python
    response = s3.get_object(Bucket='your-bucket-name', Key='greetings/hello.json')
    content = response['Body'].read().decode('utf-8')
    print(content)
    ```

---

## Exercise

Upload a JSON object to your bucket using the language of your choice, then verify it arrived using
the AWS CLI:

```shell
aws s3 ls s3://your-bucket-name/greetings/ --region eu-west-1
```

Download it back using the SDK and print the contents to confirm the round-trip works.
