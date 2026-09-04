# Create and Connect the App

The Quarkus app in `app/` is a simple todo API. Out of the box it stores todos in memory — nothing
persists across restarts. In this section you'll wire it to the AWS services you've already
provisioned: first DynamoDB (persistent storage), then S3 (backup on every write).

The app uses the AWS SDK for Java v2. It authenticates via the
[Default Credential Provider Chain](https://docs.aws.amazon.com/sdk-for-java/latest/developer-guide/credentials-chain.html),
so it picks up your SSO session automatically — no access keys in the code or config.

## Running the app locally

Set the two environment variables the app reads at startup, then launch Quarkus in dev mode:

=== "Linux / macOS"

    ```shell
    cd app

    export DYNAMODB_TABLE_NAME=<your-table-name>
    export S3_BUCKET_NAME=<your-bucket-name>

    ./mvnw quarkus:dev
    ```

=== "Windows (PowerShell)"

    ```powershell
    cd app

    $env:DYNAMODB_TABLE_NAME = "<your-table-name>"
    $env:S3_BUCKET_NAME = "<your-bucket-name>"

    ./mvnw quarkus:dev
    ```

The app starts on port 8080. You can use `curl`, a REST client, or the Quarkus Dev UI at
`http://localhost:8080/q/dev`.

!!! note "Make sure your SSO session is active"
    The SDK picks up credentials from `~/.aws/sso/cache/`. Run
    `aws sso login --profile traineeship` before starting the app if your session has expired.

---

## DynamoDB — persistent storage

### What the code does

Open `DynamoDbRepository.java`:

```java
// Uncomment @ApplicationScoped (and remove it from InMemoryRepository) to activate.
// @ApplicationScoped
public class DynamoDbRepository implements TodoRepository {

    private static final String TABLE_NAME = System.getenv("DYNAMODB_TABLE_NAME");

    private final DynamoDbClient dynamoDbClient;

    public DynamoDbRepository() {
        this.dynamoDbClient = DynamoDbClient.builder()
                .region(Region.EU_WEST_1)
                .build();
    }

    @Override
    public List<Todo> getAll() {
        ScanResponse response = dynamoDbClient.scan(
                ScanRequest.builder().tableName(TABLE_NAME).build());
        return response.items()
                .stream()
                .map(item -> new Todo(item.get("title").s()))
                .collect(Collectors.toList());
    }

    @Override
    public void create(Todo todo) {
        dynamoDbClient.putItem(PutItemRequest.builder()
                .tableName(TABLE_NAME)
                .item(Map.of("title", AttributeValue.fromS(todo.title())))
                .build());
    }
}
```

- `getAll()` does a full table **Scan** and maps each item's `title` attribute to a `Todo` object.
- `create()` calls **PutItem** with a single string attribute — matching the `title` partition key
  defined in the Terraform module.
- The table name is injected via `DYNAMODB_TABLE_NAME` so the same code works locally and in ECS.

### Activate it

`DynamoDbRepository` and `InMemoryRepository` both implement `TodoRepository`. CDI picks whichever
one is annotated `@ApplicationScoped`. To switch:

1. In `DynamoDbRepository.java`, uncomment `@ApplicationScoped`.
2. In `InMemoryRepository.java`, remove `@ApplicationScoped`.

### Verify

With the app running, create a todo:

```shell
curl -s -X POST http://localhost:8080/todo \
  -H "Content-Type: application/json" \
  -d '{"title": "learn DynamoDB"}'
```

Then confirm it landed in the table:

```shell
aws dynamodb scan \
  --table-name <your-table-name> \
  --region eu-west-1
```

You should see the item in the response. Restart the app (`Ctrl+C`, then `./mvnw quarkus:dev`
again) and call `GET /todo` — the item is still there, now coming from DynamoDB rather than memory.

---

## S3 — backup on write

### What the code does

Open `S3BackupListener.java`:

```java
@ApplicationScoped
public class S3BackupListener {

    private static final String BUCKET_NAME = System.getenv("S3_BUCKET_NAME");

    private final S3Client s3Client;

    public S3BackupListener() {
        this.s3Client = S3Client.builder()
                .region(Region.EU_WEST_1)
                .build();
    }

    public void onCreated(Todo todo) {
        // Uncomment to back up each new todo to S3 as a JSON object.
        // String key = "todos/" + System.currentTimeMillis() + ".json";
        // s3Client.putObject(
        //         PutObjectRequest.builder()
        //                 .bucket(BUCKET_NAME)
        //                 .key(key)
        //                 .contentType("application/json")
        //                 .build(),
        //         RequestBody.fromString("{\"title\":\"" + todo.title() + "\"}"));
    }
}
```

`onCreated` is called from `TodoServiceImpl` every time a todo is created. Right now it's a no-op.
When you uncomment the body, each create request uploads a small JSON object to the `todos/`
prefix of your bucket — keyed by the current timestamp so every write produces a unique object.

### Activate it

Uncomment the four lines inside `onCreated` in `S3BackupListener.java`.

### Verify

Create another todo:

```shell
curl -s -X POST http://localhost:8080/todo \
  -H "Content-Type: application/json" \
  -d '{"title": "learn S3"}'
```

Then list the objects in your bucket:

```shell
aws s3 ls s3://<your-bucket-name>/todos/ --region eu-west-1
```

You should see a `.json` file appear under `todos/`. Download and inspect it:

=== "Linux / macOS"

    ```shell
    aws s3 cp \
      s3://<your-bucket-name>/todos/<the-key-from-ls>.json \
      - --region eu-west-1
    ```

=== "Windows (PowerShell)"

    ```powershell
    aws s3 cp `
      s3://<your-bucket-name>/todos/<the-key-from-ls>.json `
      - --region eu-west-1
    ```

---

## Key takeaways

- The Default Credential Provider Chain means no credentials in code — the same app binary works
  locally (SSO session) and in ECS (task role), with no code change.
- Switching from `InMemoryRepository` to `DynamoDbRepository` is a single CDI annotation swap —
  the rest of the app doesn't change.
- `S3BackupListener` is always wired in by CDI; only the upload body is toggled. This is a common
  pattern for feature flags in CDI apps.
- When the app moves to ECS (later module), `DYNAMODB_TABLE_NAME` and `S3_BUCKET_NAME` are
  injected by the task definition — the same env-var contract works both locally and in the cloud.
