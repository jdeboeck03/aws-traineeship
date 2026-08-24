# Lambda — Serverless Functions

[AWS Lambda](https://aws.amazon.com/lambda/) lets you run code without managing servers. You
upload a function, choose a trigger, and AWS handles scaling, retries, and patching. You pay only
for the milliseconds your function runs.

Two triggers are covered here:

- **EventBridge schedule** — invoke the function on a cron/rate expression
- **SQS event source mapping** — Lambda polls the queue and invokes the function when messages
  arrive; no polling loop needed in your code

!!! warning "Lambda consumer vs. in-app consumer"
    The todo app's `QueueConsumer` and the Lambda consumer both read from the same SQS queue.
    SQS delivers each message to exactly one receiver, so keep one or the other active — not both.

---

!!! info "No manual exercise for this module"
    From VPC onwards, modules go straight to Terraform. The IAM role, EventBridge rule, and event
    source mapping are easier to follow in Terraform where all the pieces are visible at once.

---

## `terraform/lambda/`

```
terraform/lambda/
├── function/
│   ├── producer.py   # EventBridge → SNS publish
│   └── consumer.py   # SQS event source mapping
├── main.tf
├── variables.tf
└── outputs.tf
```

### The functions

```python title="function/producer.py"
import json, os, random
import boto3

sns = boto3.client("sns")
TOPIC_ARN = os.environ["SNS_TOPIC_ARN"]

TITLES = ["Buy milk", "Walk the dog", "Call the dentist",
          "Read a book", "Fix the tests", "Write docs",
          "Deploy to prod", "Review the PR"]

def handler(event, context):
    title = random.choice(TITLES)
    sns.publish(TopicArn=TOPIC_ARN, Message=json.dumps({"title": title}))
    print(f"Published todo: {title}")
```

```python title="function/consumer.py"
import json

def handler(event, context):
    for record in event["Records"]:
        body = json.loads(record["body"])
        # SNS wraps the message in an envelope when delivered via SNS → SQS.
        if "Message" in body:
            payload = json.loads(body["Message"])
        else:
            payload = body
        print(f"Consumed todo: {payload.get('title', payload)}")
```

### `main.tf`

```hcl title="main.tf"
# Package .py files into zips at plan time.
# source_code_hash detects edits and triggers a redeployment automatically.
data "archive_file" "producer" {
  type        = "zip"
  source_file = "${path.module}/function/producer.py"
  output_path = "${path.module}/function/producer.zip"
}

data "archive_file" "consumer" {
  type        = "zip"
  source_file = "${path.module}/function/consumer.py"
  output_path = "${path.module}/function/consumer.zip"
}

# Create log groups explicitly so retention is set before the first invocation.
# Lambda auto-creates them on first run, but without a retention policy.
resource "aws_cloudwatch_log_group" "producer" {
  name              = "/aws/lambda/${var.name}-producer"
  retention_in_days = 7
  tags = { Name = "${var.name}-producer-logs" }
}

resource "aws_cloudwatch_log_group" "consumer" {
  name              = "/aws/lambda/${var.name}-consumer"
  retention_in_days = 7
  tags = { Name = "${var.name}-consumer-logs" }
}

# --- Producer role ---

resource "aws_iam_role" "producer" {
  name = "${var.name}-lambda-producer-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = { Name = "${var.name}-lambda-producer-role" }
}

resource "aws_iam_role_policy_attachment" "producer_basic" {
  role       = aws_iam_role.producer.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "producer_sns" {
  name = "${var.name}-lambda-producer-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sns:Publish"
      Resource = var.sns_topic_arn
    }]
  })
  tags = { Name = "${var.name}-lambda-producer-policy" }
}

resource "aws_iam_role_policy_attachment" "producer_sns" {
  role       = aws_iam_role.producer.name
  policy_arn = aws_iam_policy.producer_sns.arn
}

# --- Producer function + EventBridge schedule ---

resource "aws_lambda_function" "producer" {
  function_name    = "${var.name}-producer"
  handler          = "producer.handler"
  runtime          = "python3.12"
  role             = aws_iam_role.producer.arn
  filename         = data.archive_file.producer.output_path
  source_code_hash = data.archive_file.producer.output_base64sha256

  environment {
    variables = { SNS_TOPIC_ARN = var.sns_topic_arn }
  }

  depends_on = [aws_cloudwatch_log_group.producer]
  tags = { Name = "${var.name}-producer" }
}

resource "aws_cloudwatch_event_rule" "schedule" {
  name                = "${var.name}-producer-schedule"
  schedule_expression = "rate(1 minute)"
  tags = { Name = "${var.name}-producer-schedule" }
}

resource "aws_cloudwatch_event_target" "producer" {
  rule = aws_cloudwatch_event_rule.schedule.name
  arn  = aws_lambda_function.producer.arn
}

# Lambda requires a resource-based policy allowing EventBridge to invoke it.
# An IAM role alone is not enough for cross-service triggers.
resource "aws_lambda_permission" "eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.producer.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.schedule.arn
}

# --- Consumer role ---
# AWSLambdaSQSQueueExecutionRole bundles CloudWatch Logs write access with the
# SQS permissions Lambda needs to poll and delete messages on your behalf.

resource "aws_iam_role" "consumer" {
  name = "${var.name}-lambda-consumer-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = { Name = "${var.name}-lambda-consumer-role" }
}

resource "aws_iam_role_policy_attachment" "consumer_sqs" {
  role       = aws_iam_role.consumer.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaSQSQueueExecutionRole"
}

# --- Consumer function + SQS event source mapping ---

resource "aws_lambda_function" "consumer" {
  function_name    = "${var.name}-consumer"
  handler          = "consumer.handler"
  runtime          = "python3.12"
  role             = aws_iam_role.consumer.arn
  filename         = data.archive_file.consumer.output_path
  source_code_hash = data.archive_file.consumer.output_base64sha256

  depends_on = [aws_cloudwatch_log_group.consumer]
  tags = { Name = "${var.name}-consumer" }
}

resource "aws_lambda_event_source_mapping" "sqs" {
  event_source_arn = var.sqs_queue_arn
  function_name    = aws_lambda_function.consumer.arn
  batch_size       = 10
  enabled          = true
}
```

### `variables.tf`

```hcl title="variables.tf"
variable "name" {
  description = "Prefix used for all resource names."
  type        = string
}

variable "sns_topic_arn" {
  description = "ARN of the SNS topic the producer Lambda publishes to."
  type        = string
}

variable "sqs_queue_arn" {
  description = "ARN of the SQS queue the consumer Lambda reads from."
  type        = string
}
```

### `outputs.tf`

```hcl title="outputs.tf"
output "producer_function_name" {
  description = "Name of the scheduled producer Lambda function."
  value       = aws_lambda_function.producer.function_name
}

output "consumer_function_name" {
  description = "Name of the SQS consumer Lambda function."
  value       = aws_lambda_function.consumer.function_name
}
```

### Wire it into the full stack

Add to `terraform/full-stack/main.tf`:

```hcl title="terraform/full-stack/main.tf"
module "lambda" {
  source = "../lambda"
  name   = var.name

  sns_topic_arn = module.sns.topic_arn
  sqs_queue_arn = module.sqs.queue_arn
}
```

Also add the `archive` provider to the `required_providers` block:

```hcl
archive = {
  source  = "hashicorp/archive"
  version = "~> 2.0"
}
```

### Apply

```shell
cd terraform/full-stack

terraform init   # picks up the lambda module + archive provider
terraform plan
terraform apply
```

---

## Verify

Tail the producer's log group — you should see a new entry every minute:

=== "Linux / macOS"

    ```shell
    FUNC=$(terraform output -raw producer_function_name)
    aws logs tail "/aws/lambda/$FUNC" --follow
    ```

=== "Windows (PowerShell)"

    ```powershell
    $func = terraform output -raw producer_function_name
    aws logs tail "/aws/lambda/$func" --follow
    ```

To trigger it immediately without waiting for the schedule:

=== "Linux / macOS"

    ```shell
    aws lambda invoke --function-name "$FUNC" --payload '{}' /tmp/out.json
    ```

=== "Windows (PowerShell)"

    ```powershell
    aws lambda invoke --function-name $func --payload '{}' $env:TEMP\out.json
    ```

The consumer is invoked automatically when messages arrive in the queue. Check its log group
in the same way using `consumer_function_name`.

---

## Clean up

```shell
terraform destroy
```
