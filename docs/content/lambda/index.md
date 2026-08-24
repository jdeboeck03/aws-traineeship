# Lambda

[AWS Lambda](https://aws.amazon.com/lambda/) lets you run code without managing servers. You
upload a function, choose a trigger, and AWS handles the rest. Two triggers are covered here: an
**EventBridge schedule** (run every minute) and an **SQS event source mapping** (Lambda polls the
queue automatically — no polling loop in your code).

## Functions

```python title="terraform/lambda/function/producer.py"
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

```python title="terraform/lambda/function/consumer.py"
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

## `terraform/lambda/`

```hcl title="main.tf"
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

# Explicit log groups so retention is set before the first invocation.
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

# Lambda also needs a resource-based policy to allow EventBridge to invoke it.
resource "aws_lambda_permission" "eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.producer.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.schedule.arn
}

# AWSLambdaSQSQueueExecutionRole bundles CloudWatch Logs + the SQS permissions
# Lambda needs to poll and delete messages on your behalf.
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

```hcl title="variables.tf"
variable "name" {
  type = string
}

variable "sns_topic_arn" {
  type = string
}

variable "sqs_queue_arn" {
  type = string
}
```

```hcl title="outputs.tf"
output "producer_function_name" {
  value = aws_lambda_function.producer.function_name
}

output "consumer_function_name" {
  value = aws_lambda_function.consumer.function_name
}
```

## Wire it into the full stack

```hcl title="terraform/full-stack/main.tf"
module "lambda" {
  source = "../lambda"
  name   = var.name

  sns_topic_arn = module.sns.topic_arn
  sqs_queue_arn = module.sqs.queue_arn
}
```

Add the `archive` provider to `required_providers`:

```hcl
archive = {
  source  = "hashicorp/archive"
  version = "~> 2.0"
}
```

## Apply

```shell
cd terraform/full-stack

terraform init
terraform plan
terraform apply
```

## Verify

Tail the producer log group — a new line should appear every minute:

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
