# Create and Connect the App

In this section you'll build a Quarkus todo API and wire it to the AWS services you've already
provisioned: DynamoDB for persistent storage and S3 for a backup on every write.

The app uses the AWS SDK for Java v2. It authenticates via the
[Default Credential Provider Chain](https://docs.aws.amazon.com/sdk-for-java/latest/developer-guide/credentials-chain.html)
— the same code that picks up your local SSO session will automatically use the ECS task role
when the app runs in the cloud. No credentials in code or config.

!!! tip "Starting point"
    You need a working Quarkus todo API before continuing. If you don't have one yet, generate a
    project at [code.quarkus.io](https://code.quarkus.io) with **RESTEasy** and
    **RESTEasy Jackson**, then add `GET /todo` and `POST /todo` endpoints backed by an in-memory
    store.

---

## Dependencies

Add the AWS SDK BOM to `dependencyManagement` (so all SDK modules share one version), then pull
in the modules you need:

```
software.amazon.awssdk:bom          ← version lock, type pom, scope import
software.amazon.awssdk:dynamodb
software.amazon.awssdk:s3
software.amazon.awssdk:netty-nio-client
```

---

## Running the app locally

Set the environment variables the app reads at startup, then launch Quarkus in dev mode:

=== "Linux / macOS"

    ```shell
    export DYNAMODB_TABLE_NAME=<your-table-name>
    export S3_BUCKET_NAME=<your-bucket-name>

    ./mvnw quarkus:dev
    ```

=== "Windows (PowerShell)"

    ```powershell
    $env:DYNAMODB_TABLE_NAME = "<your-table-name>"
    $env:S3_BUCKET_NAME = "<your-bucket-name>"

    ./mvnw quarkus:dev
    ```

The app starts on port 8080.

!!! note "Make sure your SSO session is active"
    Run `aws sso login --profile traineeship` before starting the app if your session has expired.

---

## DynamoDB — persistent storage

### The repository

Create a `DynamoDbRepository` that implements your `TodoRepository` interface:

```java
@ApplicationScoped
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

- `getAll()` runs a full table **Scan** and maps each item's `title` attribute back to a `Todo`.
- `create()` calls **PutItem** with a single string attribute — matching the `title` partition key
  defined in your Terraform module.
- The table name comes from `DYNAMODB_TABLE_NAME` so the same binary works locally and in ECS.

!!! tip "CDI picks exactly one implementation"
    CDI resolves `TodoRepository` to whichever implementation carries `@ApplicationScoped`. If
    you have an `InMemoryRepository` with that annotation, remove it — otherwise CDI sees two
    candidates and fails to start.

### Verify

Create a todo:

```shell
curl -s -X POST http://localhost:8080/todo \
  -H "Content-Type: application/json" \
  -d '{"title": "learn DynamoDB"}'
```

Confirm it landed in the table:

```shell
aws dynamodb scan \
  --table-name <your-table-name> \
  --region eu-west-1
```

Restart the app and call `GET /todo` — the item is still there, now coming from DynamoDB rather
than memory.

---

## S3 — backup on write

### The listener

Create an `S3BackupListener` that uploads a JSON object to S3 every time a todo is created:

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
        String key = "todos/" + System.currentTimeMillis() + ".json";
        s3Client.putObject(
                PutObjectRequest.builder()
                        .bucket(BUCKET_NAME)
                        .key(key)
                        .contentType("application/json")
                        .build(),
                RequestBody.fromString("{\"title\":\"" + todo.title() + "\"}"));
    }
}
```

Using the current timestamp as the key ensures every write produces a unique object under the
`todos/` prefix.

### Wire it into your service

Inject `S3BackupListener` into your service and call `onCreated` after each create:

```java
@ApplicationScoped
public class TodoServiceImpl implements TodoService {

    private final TodoRepository repository;
    private final S3BackupListener s3Backup;

    public TodoServiceImpl(TodoRepository repository, S3BackupListener s3Backup) {
        this.repository = repository;
        this.s3Backup = s3Backup;
    }

    @Override
    public List<Todo> getAll() {
        return repository.getAll();
    }

    @Override
    public void create(Todo todo) {
        repository.create(todo);
        s3Backup.onCreated(todo);
    }
}
```

### Verify

Create a todo:

```shell
curl -s -X POST http://localhost:8080/todo \
  -H "Content-Type: application/json" \
  -d '{"title": "learn S3"}'
```

List the objects in your bucket:

```shell
aws s3 ls s3://<your-bucket-name>/todos/ --region eu-west-1
```

You should see a `.json` file under `todos/`. Download and inspect it:

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

- The Default Credential Provider Chain means no credentials in code — the same binary works
  locally (SSO session) and in ECS (task role) without any changes.
- CDI resolves `TodoRepository` to whichever implementation is `@ApplicationScoped` — switching
  storage backends is a single annotation change.
- `S3BackupListener` is a plain CDI bean called explicitly from the service — nothing framework-
  specific, straightforward to test.
- When the app moves to ECS, `DYNAMODB_TABLE_NAME` and `S3_BUCKET_NAME` are injected by the task
  definition — the same env-var contract works both locally and in the cloud.
