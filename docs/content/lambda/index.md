# Lambda — Serverless Functions

Lambda lets you run code without provisioning or managing servers. You upload a function, choose a
trigger, and AWS handles the rest — scaling, retries, patching. You pay only for the milliseconds
your function runs.

Two common patterns:
- **Schedule** — run code periodically (EventBridge cron/rate expression)
- **Event source** — run code in response to messages arriving in a queue (SQS event source
  mapping)

This module wires both into the todo architecture: a **producer** that publishes a random todo to
SNS on a schedule, and a **consumer** that reads from the SQS queue.

## Concepts

**Handler**
The entry point of a Lambda function. The runtime calls `handler(event, context)` on each
invocation. `event` contains the trigger-specific payload (EventBridge schedules send a small JSON
object; SQS triggers send a batch of records). `context` has metadata like the request ID and
remaining execution time.

**Runtime**
The language environment Lambda runs your code in. AWS manages runtime patching. Supported
runtimes include Python 3.12, Node.js 22, Java 21, and more. For quick scripts, Python is the
simplest choice — no build step, just zip the `.py` file.

**Execution role**
Every Lambda function has an IAM role that defines what AWS services it can call. Lambda assumes
this role on each invocation. It follows exactly the same IAM model as EC2 instance profiles and
ECS task roles — the principal just changes to `lambda.amazonaws.com`.

**Trigger**
The event source that invokes the function. EventBridge rules push an event to Lambda at a
scheduled time. SQS event source mappings cause Lambda to poll the queue and invoke the function
with a batch of messages.

**Cold start**
When Lambda needs to run a function that has no warm container available, it initialises a new
execution environment — downloading the code, starting the runtime, running any initialisation
code outside the handler. This takes a few hundred milliseconds. Subsequent invocations of the
same container are warm and much faster. Python cold starts are typically under 100 ms for small
functions.

**SQS event source mapping**
Lambda maintains a long-polling connection to the queue and invokes the function when messages
arrive. Lambda handles the polling loop, the receive/delete lifecycle, and batch retries — the
function code only needs to process the messages it receives. If the function throws, Lambda
retries the batch (up to the SQS visibility timeout). Messages that fail repeatedly end up in the
dead-letter queue.

!!! warning "Lambda consumer vs. in-app consumer"
    The todo app's `QueueConsumer` (currently commented out) and the Lambda consumer both read from
    the same SQS queue. SQS delivers each message to exactly one receiver, so running both at the
    same time splits the messages unpredictably between them. Keep one or the other active — not
    both.

!!! note "Free tier"
    Lambda includes 1 million free invocations and 400,000 GB-seconds of compute per month,
    permanently (not just the first year). A function running once a minute is ~43,000 invocations
    per month — well inside the free tier. Verify current rates at
    [aws.amazon.com/lambda/pricing](https://aws.amazon.com/lambda/pricing).

---

!!! info "No manual exercise for this module"
    Lambda has a console wizard, but the IAM role, EventBridge rule, and event source mapping are
    easier to follow in Terraform where all the pieces are visible at once.

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
import json
import os
import random

import boto3

sns = boto3.client("sns")
TOPIC_ARN = os.environ["SNS_TOPIC_ARN"]

TITLES = [
    "Buy milk", "Walk the dog", "Call the dentist",
    "Read a book", "Fix the tests", "Write docs",
    "Deploy to prod", "Review the PR",
]


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

The producer publishes to SNS, which fans the message out to the SQS queue (and any other
subscribers). The consumer receives it from the queue. Both functions are intentionally short —
the interesting part is the AWS plumbing, not the application logic.

### `main.tf` — packaging

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
```

`archive_file` is a Terraform data source (from the `hashicorp/archive` provider) that zips the
file at plan time. `source_code_hash` on the Lambda resource is set to
`output_base64sha256` — this forces a redeployment whenever the Python file changes, even if
the function name didn't. Without it, editing the code would have no effect until you taint the
resource manually.

### `main.tf` — log groups

```hcl title="main.tf"
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
```

Lambda auto-creates a log group named `/aws/lambda/<function-name>` on the first invocation if
one doesn't exist — but without a retention policy, logs accumulate forever. Creating the group
explicitly with `depends_on` on the function ensures retention is set before any logs arrive.

### `main.tf` — producer role

```hcl title="main.tf"
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
```

`AWSLambdaBasicExecutionRole` is an AWS-managed policy that grants CloudWatch Logs write access —
the bare minimum every Lambda function needs. The custom policy adds `sns:Publish` scoped to the
specific topic. Two attachments, two concerns — follows the same principle as the EC2 instance
profile and ECS task role.

### `main.tf` — producer function + EventBridge schedule

```hcl title="main.tf"
resource "aws_lambda_function" "producer" {
  function_name = "${var.name}-producer"
  handler       = "producer.handler"
  runtime       = "python3.12"
  role          = aws_iam_role.producer.arn

  filename         = data.archive_file.producer.output_path
  source_code_hash = data.archive_file.producer.output_base64sha256

  environment {
    variables = {
      SNS_TOPIC_ARN = var.sns_topic_arn
    }
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

resource "aws_lambda_permission" "eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.producer.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.schedule.arn
}
```

Three resources are needed for the EventBridge trigger:

1. `aws_cloudwatch_event_rule` — the schedule itself. `rate(1 minute)` fires every 60 seconds.
   You can also use cron expressions: `cron(0 9 ? * MON-FRI *)` for weekday mornings at 09:00 UTC.
2. `aws_cloudwatch_event_target` — points the rule at the Lambda ARN.
3. `aws_lambda_permission` — a **resource-based policy** on the Lambda function that allows
   EventBridge to invoke it. IAM roles alone aren't enough for cross-service invocations; Lambda
   also checks a resource-based policy on the function itself. Without this, the rule fires but
   EventBridge gets an `AccessDenied` and the function is never called.

### `main.tf` — consumer role + function + event source mapping

```hcl title="main.tf"
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
  function_name = "${var.name}-consumer"
  handler       = "consumer.handler"
  runtime       = "python3.12"
  role          = aws_iam_role.consumer.arn

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

`AWSLambdaSQSQueueExecutionRole` bundles CloudWatch Logs write access with the SQS permissions
Lambda needs to poll and delete messages on your behalf: `ReceiveMessage`, `DeleteMessage`,
`GetQueueAttributes`, `ChangeMessageVisibility`. You don't write any polling logic — the event
source mapping handles it. Lambda invokes the consumer with a batch of up to 10 messages, then
deletes them only if the function returns successfully.

### Wire into the full stack

Add the Lambda module to `terraform/full-stack/main.tf`:

```hcl title="terraform/full-stack/main.tf"
module "lambda" {
  source = "../lambda"
  name   = var.name

  sns_topic_arn = module.sns.topic_arn
  sqs_queue_arn = module.sqs.queue_arn
}
```

Also add the `archive` provider to `terraform/full-stack/main.tf`'s `required_providers` block:

```hcl title="terraform/full-stack/main.tf"
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

### Producer: CloudWatch Logs

After a minute or two, check the producer's log group for output:

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

You should see lines like `Published todo: Buy milk` appearing every minute. Press `Ctrl+C` to
stop tailing.

### Producer: invoke manually

You can invoke a Lambda function directly from the CLI — useful for testing without waiting for
the schedule:

=== "Linux / macOS"

    ```shell
    aws lambda invoke \
      --function-name "$FUNC" \
      --payload '{}' \
      /tmp/response.json

    cat /tmp/response.json
    ```

=== "Windows (PowerShell)"

    ```powershell
    aws lambda invoke `
      --function-name $func `
      --payload '{}' `
      $env:TEMP\response.json

    Get-Content $env:TEMP\response.json
    ```

The response should be `{"statusCode": 200}` (Lambda's default) and the log group gets a new
entry.

### Consumer: CloudWatch Logs

After the producer runs and the SQS queue receives messages, the consumer is invoked
automatically. Tail its log group:

=== "Linux / macOS"

    ```shell
    CONSUMER=$(terraform output -raw consumer_function_name)

    aws logs tail "/aws/lambda/$CONSUMER" --follow
    ```

=== "Windows (PowerShell)"

    ```powershell
    $consumer = terraform output -raw consumer_function_name

    aws logs tail "/aws/lambda/$consumer" --follow
    ```

You should see `Consumed todo: Buy milk` (or similar) — the message published by the producer,
routed through SNS → SQS → Lambda.

### Check the queue depth

If messages are piling up instead of being consumed, check the queue:

=== "Linux / macOS"

    ```shell
    QUEUE_URL=$(terraform output -raw sqs_queue_url)

    aws sqs get-queue-attributes \
      --queue-url "$QUEUE_URL" \
      --attribute-names ApproximateNumberOfMessages \
                        ApproximateNumberOfMessagesNotVisible
    ```

=== "Windows (PowerShell)"

    ```powershell
    $queueUrl = terraform output -raw sqs_queue_url

    aws sqs get-queue-attributes `
      --queue-url $queueUrl `
      --attribute-names ApproximateNumberOfMessages `
                        ApproximateNumberOfMessagesNotVisible
    ```

`ApproximateNumberOfMessages` is the visible backlog. If it keeps growing, the consumer function
may be erroring — check its log group.

---

## How the pieces fit together

```
EventBridge (rate: 1 minute)
    │
    └─► producer Lambda ──► SNS topic
                                │
                                └─► SQS queue ──► consumer Lambda
                                                        │
                                                        └─► CloudWatch Logs
```

Every minute, EventBridge fires the producer. The producer picks a random todo title and
publishes it to SNS. SNS delivers it to the SQS queue. The event source mapping detects the
message and invokes the consumer. The consumer logs it and Lambda deletes the message from the
queue.

---

## Clean up

```shell
terraform destroy
```

Note: `terraform destroy` also removes the EventBridge rule and the event source mapping — the
queue stops receiving messages and Lambda stops polling. The Lambda function zip files
(`function/producer.zip`, `function/consumer.zip`) are local artefacts created by the
`archive_file` data source; they are not uploaded to S3 and are safe to delete manually.

---

## Key takeaways

- Lambda runs code without managing servers — you define the handler, runtime, and role.
- EventBridge schedules fire Lambda on a cron/rate expression. Three resources are needed: the
  **rule**, a **target** pointing at the function ARN, and a **resource-based policy** on the
  function (`aws_lambda_permission`) allowing EventBridge to invoke it.
- SQS event source mappings replace your polling loop — Lambda polls, batches, and handles
  delete. The function only processes the messages it receives.
- `AWSLambdaBasicExecutionRole` (CloudWatch Logs) is the baseline every function needs.
  `AWSLambdaSQSQueueExecutionRole` bundles that with SQS polling permissions.
- `source_code_hash` on the function resource detects code changes and triggers a redeployment.
  Without it, editing the Python file has no effect until you taint the resource.
- Log groups should be created explicitly with a retention period. Lambda auto-creates them on
  first invocation, but without retention logs accumulate forever.
