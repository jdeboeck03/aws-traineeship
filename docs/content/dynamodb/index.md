# DynamoDB — NoSQL Database

Amazon DynamoDB is a fully managed, serverless NoSQL database. There are no instances to provision,
no OS to patch, and no capacity to pre-plan if you choose on-demand billing. DynamoDB scales
automatically from a handful of requests to millions per second and replicates data across multiple
availability zones within a region by default.

## Concepts

**Table**
The top-level container — roughly analogous to a table in a relational database, but without a
fixed schema. Every item in a table can have a different set of attributes; only the key
attribute(s) must always be present.

**Item**
One record in a table. Analogous to a row, but schema-free: two items in the same table can have
completely different attributes as long as they share the same key.

**Attribute**
A key-value pair within an item. DynamoDB supports strings (`S`), numbers (`N`), booleans, binary
data, lists, and maps. You only define the key attributes in the table schema — all other
attributes are stored as-is and don't need to be declared up front.

**Partition key (hash key)**
A required attribute that DynamoDB uses to determine which internal partition stores the item.
Items with the same partition key end up on the same partition. If a table has only a partition
key, every item's partition key must be unique across the table.

**Sort key (range key)**
An optional second key attribute. When a table has both a partition key and a sort key, the
*combination* of the two must be unique — multiple items can share the same partition key as long
as they have different sort keys. Items with the same partition key are stored together and sorted
by the sort key, which enables efficient range queries (`begins_with`, `between`, `<`, `>`) within
a partition.

!!! note "Key design is the most important decision"
    In a relational database you can add an index later and pay a modest cost. In DynamoDB the
    partition key determines physical data placement: a hot partition (one that receives most of
    the traffic) cannot be rebalanced without changing the key schema and migrating data. Think
    about your access patterns before picking a partition key.

**Billing mode**
DynamoDB offers two pricing models:

- **Provisioned** — you specify the number of read and write capacity units per second upfront.
  Cheaper at predictable, sustained load; requires capacity planning and auto-scaling configuration.
- **On-demand (`PAY_PER_REQUEST`)** — you pay per request with no capacity planning. Scales
  automatically to any load. Better for variable or unpredictable traffic and for getting started.

!!! note "Free tier"
    DynamoDB is free-tier eligible: 25 GB of storage and 25 read/write capacity units per month
    (provisioned), or approximately 200 million on-demand requests per month, at no charge — with
    no 12-month expiry. Verify current limits at
    [aws.amazon.com/free](https://aws.amazon.com/free).

**Global Secondary Index (GSI)**
An alternate key definition that spans the entire table. A GSI lets you query by a different
partition key (and optional sort key) than the table's primary key — for example, query todos by
`status` even though the primary key is `title`. GSIs replicate data asynchronously and incur
additional storage and request costs. They're not used in this module but are the standard
solution when your access patterns outgrow the primary key.

**Server-side encryption (SSE)**
DynamoDB encrypts all data at rest. By default it uses an AWS-owned key at no extra charge.
Enabling SSE explicitly in your Terraform config (`server_side_encryption { enabled = true }`)
makes this visible and auditable — the behaviour is the same but the intent is documented in code.

---

!!! info "No manual exercise for this module"
    From VPC onwards, modules go straight to Terraform. DynamoDB tables have almost no interesting
    configuration in the console beyond what Terraform expresses more clearly in code — and manual
    cleanup is error-prone when multiple trainees share the same account.

    EC2 is the exception: launching an instance manually first makes AMIs, key pairs, and security
    groups concrete before Terraform abstracts them away.

## Provisioning with Terraform

The DynamoDB module creates a single table with a `title` partition key. That key matches the
model used by the Quarkus app: a todo item identified by its title.

### `terraform/dynamodb/`

```
terraform/dynamodb/
├── main.tf
├── variables.tf
└── outputs.tf
```

```hcl title="main.tf"
resource "aws_dynamodb_table" "this" {
  name         = var.name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "title"

  attribute {
    name = "title"
    type = "S"
  }

  server_side_encryption {
    enabled = true
  }

  tags = {
    Name = var.name
  }
}
```

`billing_mode = "PAY_PER_REQUEST"` means no capacity planning — DynamoDB scales automatically and
you pay per request. The `attribute` block only declares the key attribute (`title`); all other
attributes a todo item might carry are stored as-is without being declared here.

```hcl title="variables.tf"
variable "name" {
  description = "Unique name used as the DynamoDB table name and Name tag."
  type        = string
}
```

The `name` variable doubles as the table name, keeping it unique per trainee without needing a
separate `table_name` variable.

```hcl title="outputs.tf"
output "table_name" {
  description = "Name of the DynamoDB table."
  value       = aws_dynamodb_table.this.name
}

output "table_arn" {
  description = "ARN of the DynamoDB table."
  value       = aws_dynamodb_table.this.arn
}
```

### Wire it into the full stack

Add the DynamoDB module to `terraform/full-stack/main.tf` and pass its ARN to the IAM module so
the EC2 instance role gains permission to read and write the table:

```hcl title="terraform/full-stack/main.tf"
module "dynamodb" {
  source = "../dynamodb"
  name   = var.name
}

module "iam" {
  source             = "../iam"
  name               = var.name
  bucket_name        = var.bucket_name
  dynamodb_table_arn = module.dynamodb.table_arn  # new
}
```

The IAM module now creates a scoped policy (`PutItem`, `GetItem`, `DeleteItem`, `Query`, `Scan`)
on this specific table and attaches it to the EC2 role. The Quarkus app picks up those permissions
automatically via the instance profile — no credentials needed in code.

Add the table name to `terraform/full-stack/outputs.tf`:

```hcl title="terraform/full-stack/outputs.tf"
output "dynamodb_table_name" {
  description = "Name of the DynamoDB table."
  value       = module.dynamodb.table_name
}
```

### Apply

```shell
cd terraform/full-stack

terraform init   # picks up the new dynamodb module
terraform plan
terraform apply
```

After apply, Terraform prints `dynamodb_table_name` — note it for the verify step.

### Verify

List your tables to confirm the table was created:

=== "Linux / macOS"

    ```shell
    aws dynamodb list-tables
    ```

=== "Windows (PowerShell)"

    ```powershell
    aws dynamodb list-tables
    ```

Describe the table to see its key schema and status:

=== "Linux / macOS"

    ```shell
    aws dynamodb describe-table --table-name "$(terraform output -raw dynamodb_table_name)"
    ```

=== "Windows (PowerShell)"

    ```powershell
    $table = terraform output -raw dynamodb_table_name
    aws dynamodb describe-table --table-name $table
    ```

Look for `"TableStatus": "ACTIVE"` in the output. You can also write and read a test item:

=== "Linux / macOS"

    ```shell
    TABLE=$(terraform output -raw dynamodb_table_name)

    aws dynamodb put-item \
      --table-name "$TABLE" \
      --item '{"title": {"S": "buy milk"}}'

    aws dynamodb scan --table-name "$TABLE"
    ```

=== "Windows (PowerShell)"

    ```powershell
    $table = terraform output -raw dynamodb_table_name

    aws dynamodb put-item `
      --table-name $table `
      --item '{"title": {"S": "buy milk"}}'

    aws dynamodb scan --table-name $table
    ```

### Clean up

The table is destroyed together with the rest of the stack:

```shell
terraform destroy
```

!!! warning "Destroy deletes all data"
    `terraform destroy` deletes the table and every item in it permanently. There is no
    recycle bin for DynamoDB tables.

---

## Connecting the app

The Quarkus app in `app/` uses the AWS SDK v2 (`software.amazon.awssdk:dynamodb`) to talk to the
table. The SDK automatically picks up credentials from the EC2 instance profile — no access keys
in configuration.

The key patterns:

```java title="DynamodbRepository.java"
// Build the client — picks up the instance profile credentials automatically
DynamoDbClient client = DynamoDbClient.builder()
    .region(Region.EU_WEST_1)
    .build();

// Write an item
client.putItem(PutItemRequest.builder()
    .tableName("your-name")   // matches var.name in Terraform
    .item(Map.of("title", AttributeValue.fromS(todo.title())))
    .build());

// Read all items
ScanResponse response = client.scan(
    ScanRequest.builder().tableName("your-name").build());

List<Todo> todos = response.items().stream()
    .map(item -> new Todo(item.get("title").s()))
    .collect(Collectors.toList());
```

`DynamoDbClient.builder().build()` without explicit credentials uses the **default credential
provider chain**: it checks environment variables, `~/.aws/credentials`, and finally the EC2
instance metadata service (IMDS). When running on the EC2 instance with an instance profile
attached, IMDS hands the SDK short-lived rotating credentials automatically.

!!! note "Running locally"
    When running the app locally (outside EC2), the SDK falls back to your `~/.aws` SSO profile.
    The IAM policy on the EC2 role won't apply — instead, your SSO user's permissions determine
    what the app can do. Make sure your SSO session is active (`aws sso login`) before testing
    locally.

---

## Key takeaways

- DynamoDB is schema-free at the item level — only key attributes (`hash_key`, optionally
  `range_key`) are required; all other attributes vary freely per item.
- Partition key design determines physical data placement and can't be changed after creation —
  think about access patterns before picking one.
- `PAY_PER_REQUEST` billing removes capacity planning and scales automatically; use it for
  variable traffic or while getting started.
- The EC2 instance profile (via IAM) is what lets the Quarkus app call DynamoDB without any
  credentials in code — the SDK picks them up from the instance metadata service.
- SSE encrypts data at rest by default; declaring it explicitly in Terraform makes the intent
  visible in code.
