# DynamoDB

[Amazon DynamoDB](https://aws.amazon.com/dynamodb/) is a fully managed, serverless NoSQL database.
Tables have no fixed schema — only the **partition key** (and optional sort key) must be declared
upfront; all other attributes vary freely per item. Billing mode `PAY_PER_REQUEST` removes capacity
planning and scales automatically.

## `terraform/dynamodb/`

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

```hcl title="variables.tf"
variable "name" {
  description = "Unique name used as the DynamoDB table name and Name tag."
  type        = string
}
```

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

## Wire it into the full stack

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

Add to `terraform/iam/variables.tf`:

```hcl title="terraform/iam/variables.tf"
variable "dynamodb_table_arn" {
  description = "ARN of the DynamoDB table the EC2 role is allowed to read and write."
  type        = string
}
```

Add to `terraform/iam/main.tf`:

```hcl title="terraform/iam/main.tf"
resource "aws_iam_policy" "dynamodb" {
  name = "${var.name}-dynamodb"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["dynamodb:PutItem", "dynamodb:GetItem", "dynamodb:DeleteItem",
                  "dynamodb:Query", "dynamodb:Scan"]
      Resource = var.dynamodb_table_arn
    }]
  })

  tags = { Name = "${var.name}-dynamodb" }
}

resource "aws_iam_role_policy_attachment" "dynamodb" {
  role       = aws_iam_role.ec2.name
  policy_arn = aws_iam_policy.dynamodb.arn
}
```

Add to `terraform/full-stack/outputs.tf`:

```hcl title="terraform/full-stack/outputs.tf"
output "dynamodb_table_name" {
  description = "Name of the DynamoDB table."
  value       = module.dynamodb.table_name
}
```

## Apply

```shell
cd terraform/full-stack

terraform init   # picks up the new dynamodb module
terraform plan
terraform apply
```

## Connecting the app

The Quarkus app in `app/` uses the AWS SDK v2 to talk to the table. The SDK picks up credentials
from the EC2 instance profile automatically — no access keys in configuration.

```java title="DynamoDbRepository.java"
DynamoDbClient client = DynamoDbClient.builder()
    .region(Region.EU_WEST_1)
    .build();

// Write
client.putItem(PutItemRequest.builder()
    .tableName(TABLE_NAME)
    .item(Map.of("title", AttributeValue.fromS(todo.title())))
    .build());

// Read all
ScanResponse response = client.scan(
    ScanRequest.builder().tableName(TABLE_NAME).build());
```

Activate the DynamoDB integration by swapping `@ApplicationScoped` from `InMemoryRepository` to
`DynamoDbRepository`.
