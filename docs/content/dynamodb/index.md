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

## Try it — put an item

Once applied, grab the table name from Terraform output and write an item with the AWS CLI.
DynamoDB's wire format requires a type descriptor for every attribute value (`S` = string,
`N` = number, `BOOL` = boolean, etc.).

=== "Linux / macOS"

    ```bash
    TABLE=$(terraform output -raw dynamodb_table_name)

    aws dynamodb put-item \
      --table-name "$TABLE" \
      --item '{
        "title":    {"S": "The Pragmatic Programmer"},
        "author":   {"S": "David Thomas"},
        "year":     {"N": "1999"},
        "available":{"BOOL": true}
      }'
    ```

=== "Windows (PowerShell)"

    ```powershell
    $TABLE = terraform output -raw dynamodb_table_name

    # PowerShell strips double quotes from inline strings passed to native executables.
    # Write the JSON to a temp file and use file:// instead.
    @'
    {
      "title":    {"S": "The Pragmatic Programmer"},
      "author":   {"S": "David Thomas"},
      "year":     {"N": "1999"},
      "available":{"BOOL": true}
    }
    '@ | Set-Content item.json

    aws dynamodb put-item --table-name $TABLE --item file://item.json
    Remove-Item item.json
    ```

Only `title` is required (it's the partition key). The other attributes — `author`, `year`,
`available` — are free-form; a different item could have completely different attributes.

Verify the item was written:

=== "Linux / macOS"

    ```bash
    aws dynamodb get-item \
      --table-name "$TABLE" \
      --key '{"title": {"S": "The Pragmatic Programmer"}}'
    ```

=== "Windows (PowerShell)"

    ```powershell
    @'
    {"title": {"S": "The Pragmatic Programmer"}}
    '@ | Set-Content key.json

    aws dynamodb get-item --table-name $TABLE --key file://key.json
    Remove-Item key.json
    ```