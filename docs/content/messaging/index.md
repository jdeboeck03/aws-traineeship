# Messaging — SQS and SNS

Two complementary messaging services that often appear together.

## SQS

[Amazon Simple Queue Service (SQS)](https://aws.amazon.com/sqs/) is a managed message queue.
A producer puts a message on the queue; a consumer polls, processes, then explicitly deletes it.
SQS guarantees at-least-once delivery: if the consumer doesn't call `DeleteMessage` within the
visibility timeout (default: 30 s), the message reappears and is delivered again. A dead-letter
queue (DLQ) catches messages that have been received more than `maxReceiveCount` times without
being deleted — useful for isolating poison messages.

## SNS

[Amazon Simple Notification Service (SNS)](https://aws.amazon.com/sns/) is a managed pub/sub
service. A publisher sends one message to a topic; every subscriber receives a copy immediately.
SNS pushes — it does not retain messages. Combining SNS with SQS gives durable fan-out: publish
once to SNS, it delivers to every subscribed SQS queue, each queue holds the message until its
consumer is ready.

## SQS vs SNS at a glance

| | SQS | SNS |
|---|---|---|
| Model | Queue (point-to-point) | Topic (pub/sub) |
| Delivery | Pull — consumer polls | Push — SNS delivers immediately |
| Consumers | One per message | All subscribers simultaneously |
| Message retention | Yes — waits until consumed | No — deliver or drop |
| Good for | Task queues, work distribution | Broadcasting, fan-out |

---

!!! info "No manual exercise for this module"
    From VPC onwards, modules go straight to Terraform. Creating queues and topics by hand in the
    console doesn't build meaningfully more intuition than the concepts section, and manual cleanup
    is error-prone.

---

## Step 1 — SQS queue

### `terraform/sqs/`

```
terraform/sqs/
├── main.tf
├── variables.tf
└── outputs.tf
```

```hcl title="main.tf"
resource "aws_sqs_queue" "dlq" {
  name                      = "${var.name}-dlq"
  message_retention_seconds = 1209600 # 14 days

  tags = {
    Name = "${var.name}-dlq"
  }
}

resource "aws_sqs_queue" "this" {
  name                       = "${var.name}-queue"
  visibility_timeout_seconds = 30
  message_retention_seconds  = 345600 # 4 days

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })

  tags = {
    Name = "${var.name}-queue"
  }
}
```

The DLQ is declared first because the main queue's `redrive_policy` references its ARN. Messages
received three times without being deleted are moved to the DLQ automatically.

```hcl title="variables.tf"
variable "name" {
  description = "Unique name used as a prefix for the SQS queue and DLQ names."
  type        = string
}
```

```hcl title="outputs.tf"
output "queue_url" {
  description = "URL of the SQS queue."
  value       = aws_sqs_queue.this.url
}

output "queue_arn" {
  description = "ARN of the SQS queue."
  value       = aws_sqs_queue.this.arn
}

output "dlq_url" {
  description = "URL of the dead-letter queue."
  value       = aws_sqs_queue.dlq.url
}

output "dlq_arn" {
  description = "ARN of the dead-letter queue."
  value       = aws_sqs_queue.dlq.arn
}
```

### Wire it into the full stack

Add the SQS module to `terraform/full-stack/main.tf` and pass the queue ARN to the IAM module:

```hcl title="terraform/full-stack/main.tf"
module "sqs" {
  source = "../sqs"
  name   = var.name
}

module "iam" {
  source             = "../iam"
  name               = var.name
  bucket_name        = var.bucket_name
  dynamodb_table_arn = module.dynamodb.table_arn
  sqs_queue_arn      = module.sqs.queue_arn   # new
  sns_topic_arn      = module.sns.topic_arn   # added in Step 2
}
```

Add to `terraform/iam/variables.tf`:

```hcl title="terraform/iam/variables.tf"
variable "sqs_queue_arn" {
  description = "ARN of the SQS queue the EC2 role is allowed to send and receive messages from."
  type        = string
}
```

Add to `terraform/iam/main.tf`:

```hcl title="terraform/iam/main.tf"
resource "aws_iam_policy" "sqs" {
  name = "${var.name}-sqs"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sqs:SendMessage", "sqs:ReceiveMessage",
                  "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
      Resource = var.sqs_queue_arn
    }]
  })

  tags = { Name = "${var.name}-sqs" }
}

resource "aws_iam_role_policy_attachment" "sqs" {
  role       = aws_iam_role.ec2.name
  policy_arn = aws_iam_policy.sqs.arn
}
```

Add to `terraform/full-stack/outputs.tf`:

```hcl title="terraform/full-stack/outputs.tf"
output "sqs_queue_url" {
  description = "URL of the SQS queue."
  value       = module.sqs.queue_url
}
```

### Apply

```shell
cd terraform/full-stack

terraform init   # picks up the new sqs module
terraform plan
terraform apply
```

### Verify

Send a test message, receive it, then delete it using the `ReceiptHandle` from the receive
response:

=== "Linux / macOS"

    ```shell
    QUEUE_URL=$(terraform output -raw sqs_queue_url)

    aws sqs send-message \
      --queue-url "$QUEUE_URL" \
      --message-body "hello from the CLI"

    aws sqs receive-message --queue-url "$QUEUE_URL"

    aws sqs delete-message \
      --queue-url "$QUEUE_URL" \
      --receipt-handle "<ReceiptHandle from above>"
    ```

=== "Windows (PowerShell)"

    ```powershell
    $queueUrl = terraform output -raw sqs_queue_url

    aws sqs send-message `
      --queue-url $queueUrl `
      --message-body "hello from the CLI"

    aws sqs receive-message --queue-url $queueUrl

    aws sqs delete-message `
      --queue-url $queueUrl `
      --receipt-handle "<ReceiptHandle from above>"
    ```

If you receive a message but don't delete it within 30 seconds, running `receive-message` again
returns the same message — the visibility timeout re-delivering it.

### Connecting the app

The app sends a message when a todo is created and polls the queue on a schedule:

```java title="TodoCreatedListener.java — send"
sqsClient.sendMessage(builder -> builder
    .queueUrl(QUEUE_URL)   // from terraform output sqs_queue_url
    .messageBody(todo.title())
    .build());
```

```java title="QueueConsumer.java — poll and delete"
ReceiveMessageResponse response = sqsClient.receiveMessage(
    builder -> builder.queueUrl(QUEUE_URL));

response.messages().forEach(message -> {
    log.info("Received: {}", message.body());
    sqsClient.deleteMessage(builder -> builder
        .queueUrl(QUEUE_URL)
        .receiptHandle(message.receiptHandle())
        .build());
});
```

---

## Step 2 — Add SNS

The queue is working. Now add a topic in front of it so the app publishes to SNS and the queue
subscribes. The consumer code doesn't change at all — it still reads from SQS.

### `terraform/sns/`

```
terraform/sns/
├── main.tf
├── variables.tf
└── outputs.tf
```

```hcl title="main.tf"
resource "aws_sns_topic" "this" {
  name = "${var.name}-topic"

  tags = {
    Name = "${var.name}-topic"
  }
}

resource "aws_sqs_queue_policy" "sns_to_sqs" {
  queue_url = var.queue_url

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "sns.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = var.queue_arn
      Condition = {
        ArnEquals = { "aws:SourceArn" = aws_sns_topic.this.arn }
      }
    }]
  })
}

resource "aws_sns_topic_subscription" "sqs" {
  topic_arn = aws_sns_topic.this.arn
  protocol  = "sqs"
  endpoint  = var.queue_arn
}
```

The queue policy grants SNS permission to write to the SQS queue — without it, SNS silently drops
messages. The `aws:SourceArn` condition scopes the permission to your topic only.

```hcl title="variables.tf"
variable "name" {
  description = "Unique name used as a prefix for the SNS topic name."
  type        = string
}

variable "queue_arn" {
  description = "ARN of the SQS queue that subscribes to this topic."
  type        = string
}

variable "queue_url" {
  description = "URL of the SQS queue, used to set the queue policy."
  type        = string
}
```

```hcl title="outputs.tf"
output "topic_arn" {
  description = "ARN of the SNS topic."
  value       = aws_sns_topic.this.arn
}
```

### Wire it into the full stack

```hcl title="terraform/full-stack/main.tf"
module "sns" {
  source    = "../sns"
  name      = var.name
  queue_arn = module.sqs.queue_arn
  queue_url = module.sqs.queue_url
}

module "iam" {
  # ...existing inputs...
  sns_topic_arn = module.sns.topic_arn   # new
}
```

Add to `terraform/iam/variables.tf`:

```hcl title="terraform/iam/variables.tf"
variable "sns_topic_arn" {
  description = "ARN of the SNS topic the EC2 role is allowed to publish to."
  type        = string
}
```

Add to `terraform/iam/main.tf`:

```hcl title="terraform/iam/main.tf"
resource "aws_iam_policy" "sns" {
  name = "${var.name}-sns"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sns:Publish"
      Resource = var.sns_topic_arn
    }]
  })

  tags = { Name = "${var.name}-sns" }
}

resource "aws_iam_role_policy_attachment" "sns" {
  role       = aws_iam_role.ec2.name
  policy_arn = aws_iam_policy.sns.arn
}
```

Add to `terraform/full-stack/outputs.tf`:

```hcl title="terraform/full-stack/outputs.tf"
output "sns_topic_arn" {
  description = "ARN of the SNS topic."
  value       = module.sns.topic_arn
}
```

### Apply

```shell
terraform init   # picks up the new sns module
terraform plan
terraform apply
```

### Verify

Publish to the topic, then receive from the queue:

=== "Linux / macOS"

    ```shell
    TOPIC_ARN=$(terraform output -raw sns_topic_arn)
    QUEUE_URL=$(terraform output -raw sqs_queue_url)

    aws sns publish \
      --topic-arn "$TOPIC_ARN" \
      --message "hello via SNS"

    aws sqs receive-message --queue-url "$QUEUE_URL"
    ```

=== "Windows (PowerShell)"

    ```powershell
    $topicArn = terraform output -raw sns_topic_arn
    $queueUrl = terraform output -raw sqs_queue_url

    aws sns publish `
      --topic-arn $topicArn `
      --message "hello via SNS"

    aws sqs receive-message --queue-url $queueUrl
    ```

!!! note "SNS envelope"
    The SQS message body contains a JSON envelope — the original payload is under the `"Message"`
    key. The app needs to unwrap this when reading from a topic-subscribed queue.

### Connecting the app

Switch the publisher from `SqsClient.sendMessage` to `SnsClient.publish`. The consumer is
unchanged.

```java title="TodoCreatedListener.java — publish to SNS"
snsClient.publish(builder -> builder
    .topicArn(TOPIC_ARN)   // from terraform output sns_topic_arn
    .message(todo.title())
    .build());
```

---

## Clean up

```shell
terraform destroy
```
