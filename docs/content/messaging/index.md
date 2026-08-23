# Messaging — SQS and SNS

AWS has two complementary messaging services that often appear together. This module covers both,
in order: SQS first on its own, then SNS layered on top.

## Concepts

### SQS — the to-do list

Amazon Simple Queue Service (SQS) is a managed message queue. A **producer** puts a message on the
queue; a **consumer** polls for messages, processes each one, then explicitly deletes it. The
message sits in the queue until someone picks it up.

**Queue**
The container for messages. You send to a queue URL and receive from the same URL.

**Message**
An opaque string payload (up to 256 KB). SQS doesn't interpret the content — it's the
consumer's job to parse it.

**Visibility timeout**
When a consumer receives a message, SQS hides it from other consumers for a configurable period
(default: 30 seconds). If the consumer deletes the message within that window, it's gone. If
not — because the consumer crashed, timed out, or threw an exception — the message becomes
visible again and is re-delivered. This is the mechanism behind at-least-once delivery.

!!! note "Receive, then delete"
    SQS never removes a message automatically after delivery. Your code is responsible for
    calling `DeleteMessage` after successful processing. Forgetting the delete is the most common
    SQS bug: messages keep reappearing and the consumer processes them repeatedly.

**At-least-once delivery**
SQS guarantees every message is delivered *at least* once. In rare cases (hardware failure,
network partition) it may be delivered more than once. Consumers should handle duplicate messages
gracefully — either by making operations idempotent or by tracking which messages have been
processed.

**Dead-letter queue (DLQ)**
A second queue where messages end up after too many failed delivery attempts. If a message is
received `maxReceiveCount` times (we use 3) without being deleted, SQS moves it to the DLQ
automatically. The DLQ is where you look to understand *why* messages are failing — it's a
safety net, not a primary queue.

!!! note "Free tier"
    SQS offers 1 million free requests per month with no 12-month expiry. Verify current limits at
    [aws.amazon.com/free](https://aws.amazon.com/free).

---

### SNS — the mailing list

Amazon Simple Notification Service (SNS) is a managed pub/sub service. A **publisher** sends one
message to a **topic**; all **subscribers** receive their own copy immediately. SNS pushes messages
— it doesn't hold them.

**Topic**
The named channel that publishers send to and subscribers listen on.

**Subscription**
A registered endpoint that receives a copy of every message published to the topic. SNS supports
multiple protocols: SQS queue, Lambda function, HTTP/S endpoint, email, and SMS. In this module
we use SQS.

**Fan-out**
Because every subscriber gets a copy, one `Publish` call fans out to N downstream consumers. This
is the primary reason to add SNS in front of SQS: when you have multiple independent consumers of
the same event, you publish once and let SNS deliver to each.

**Push-based delivery**
SNS delivers immediately to all subscribers when you publish. There is no polling and no message
retention — if a subscriber is down at the moment of delivery, that message is lost (unless the
subscriber is an SQS queue, which buffers it).

!!! note "Free tier"
    SNS offers 1 million publishes and 100,000 HTTP/S deliveries per month with no 12-month
    expiry. SQS deliveries from SNS are billed as SQS requests, not SNS deliveries. Verify
    current limits at [aws.amazon.com/free](https://aws.amazon.com/free).

---

### SQS vs SNS at a glance

| | SQS | SNS |
|---|---|---|
| Model | Queue (point-to-point) | Topic (pub/sub) |
| Delivery | Pull — consumer polls | Push — SNS delivers immediately |
| Consumers | One per message | All subscribers simultaneously |
| Message retention | Yes — waits until consumed | No — deliver or drop |
| Good for | Task queues, work distribution | Broadcasting, fan-out |

---

### The SNS → SQS pattern

SNS alone is fragile for durable workloads: if a subscriber is temporarily unavailable, the
message is gone. SQS alone doesn't fan out: adding a second consumer means sending to each queue
separately.

Combining them gives you both properties: publish once to SNS, SNS fans out to each subscribed
SQS queue, each queue retains the message until that consumer is ready to process it.

```
Publisher
    └─► SNS topic
             ├─► SQS queue A  (consumer A polls and processes at its own pace)
             └─► SQS queue B  (consumer B polls and processes at its own pace)
```

Today we have one queue. Tomorrow you can subscribe a second one — the publisher doesn't change.

---

!!! info "No manual exercise for this module"
    From VPC onwards, modules go straight to Terraform. Creating queues and topics by hand in the
    console doesn't build meaningfully more intuition than the concepts section, and manual cleanup
    is error-prone.

    EC2 is the exception: launching an instance manually first makes AMIs, key pairs, and security
    groups concrete before Terraform abstracts them away.

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
  message_retention_seconds  = 345600 # 4 days (default)

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })

  tags = {
    Name = "${var.name}-queue"
  }
}
```

The DLQ is declared first because the main queue's `redrive_policy` references its ARN. The
`maxReceiveCount = 3` means a message that is received three times without being deleted moves to
the DLQ — it won't keep hammering a broken consumer indefinitely. The DLQ uses a longer retention
period (14 days vs. 4) so you have time to inspect failures before they expire.

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

The IAM module gains a scoped SQS policy (`SendMessage`, `ReceiveMessage`, `DeleteMessage`,
`GetQueueAttributes`) on this specific queue. Add the following to `terraform/iam/variables.tf`:

```hcl title="terraform/iam/variables.tf"
variable "sqs_queue_arn" {
  description = "ARN of the SQS queue the EC2 role is allowed to send and receive messages from."
  type        = string
}
```

And add the policy and attachment to `terraform/iam/main.tf`:

```hcl title="terraform/iam/main.tf"
resource "aws_iam_policy" "sqs" {
  name        = "${var.name}-sqs"
  description = "Send, receive, and delete messages on the SQS queue."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
        ]
        Resource = var.sqs_queue_arn
      }
    ]
  })

  tags = { Name = "${var.name}-sqs" }
}

resource "aws_iam_role_policy_attachment" "sqs" {
  role       = aws_iam_role.ec2.name
  policy_arn = aws_iam_policy.sqs.arn
}
```

Add the queue URL to `terraform/full-stack/outputs.tf`:

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

After apply, Terraform prints `sqs_queue_url` — note it for the verify step.

### Verify

Send a test message:

=== "Linux / macOS"

    ```shell
    QUEUE_URL=$(terraform output -raw sqs_queue_url)

    aws sqs send-message \
      --queue-url "$QUEUE_URL" \
      --message-body "hello from the CLI"
    ```

=== "Windows (PowerShell)"

    ```powershell
    $queueUrl = terraform output -raw sqs_queue_url

    aws sqs send-message `
      --queue-url $queueUrl `
      --message-body "hello from the CLI"
    ```

Receive it (note the `receipt-handle` in the response — you need it to delete):

=== "Linux / macOS"

    ```shell
    aws sqs receive-message --queue-url "$QUEUE_URL"
    ```

=== "Windows (PowerShell)"

    ```powershell
    aws sqs receive-message --queue-url $queueUrl
    ```

Delete it using the `ReceiptHandle` from the receive response:

=== "Linux / macOS"

    ```shell
    aws sqs delete-message \
      --queue-url "$QUEUE_URL" \
      --receipt-handle "<ReceiptHandle from above>"
    ```

=== "Windows (PowerShell)"

    ```powershell
    aws sqs delete-message `
      --queue-url $queueUrl `
      --receipt-handle "<ReceiptHandle from above>"
    ```

!!! note "Visibility timeout in action"
    If you receive a message but don't delete it within 30 seconds, run `receive-message` again —
    you'll get the same message back. This is the visibility timeout re-delivering it.

### Connecting the app

The app sends a message when a todo is created and polls the queue on a schedule:

```java title="TodoCreatedListener.java — send"
SqsClient sqsClient = SqsClient.builder()
    .region(Region.EU_WEST_1)
    .build();

// Called after a todo is persisted to DynamoDB
sqsClient.sendMessage(builder -> builder
    .queueUrl(QUEUE_URL)   // from terraform output sqs_queue_url
    .messageBody(todo.title())
    .build());
```

```java title="QueueConsumer.java — poll and delete"
// @Scheduled(every = "10s")
public void consume() {
    ReceiveMessageResponse response = sqsClient.receiveMessage(builder ->
        builder.queueUrl(QUEUE_URL));

    response.messages().forEach(message -> {
        log.info("Received: {}", message.body());
        // process the message ...
        sqsClient.deleteMessage(builder -> builder
            .queueUrl(QUEUE_URL)
            .receiptHandle(message.receiptHandle())
            .build());
    });
}
```

The receive-then-delete contract is explicit: the `receiptHandle` returned with each message is the
token you pass to `DeleteMessage`. Without it, the message reappears after the visibility timeout.

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

# Allow SNS to write to the SQS queue.
resource "aws_sqs_queue_policy" "sns_to_sqs" {
  queue_url = var.queue_url

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "sns.amazonaws.com" }
        Action    = "sqs:SendMessage"
        Resource  = var.queue_arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_sns_topic.this.arn
          }
        }
      }
    ]
  })
}

resource "aws_sns_topic_subscription" "sqs" {
  topic_arn = aws_sns_topic.this.arn
  protocol  = "sqs"
  endpoint  = var.queue_arn
}
```

Three resources, each doing one thing. The queue policy (`aws_sqs_queue_policy`) grants SNS
permission to write to the SQS queue — without it, SNS silently drops messages because the queue
rejects them. The `Condition` on `aws:SourceArn` scopes this permission to *your* topic only; any
other SNS topic (including other trainees') cannot write to your queue. The subscription wires
topic to queue.

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

Add the SNS module to `terraform/full-stack/main.tf` and update the IAM module call:

```hcl title="terraform/full-stack/main.tf"
module "sns" {
  source    = "../sns"
  name      = var.name
  queue_arn = module.sqs.queue_arn
  queue_url = module.sqs.queue_url
}

module "iam" {
  source             = "../iam"
  name               = var.name
  bucket_name        = var.bucket_name
  dynamodb_table_arn = module.dynamodb.table_arn
  sqs_queue_arn      = module.sqs.queue_arn
  sns_topic_arn      = module.sns.topic_arn   # new
}
```

Add the SNS variable and policy to the IAM module:

```hcl title="terraform/iam/variables.tf"
variable "sns_topic_arn" {
  description = "ARN of the SNS topic the EC2 role is allowed to publish to."
  type        = string
}
```

```hcl title="terraform/iam/main.tf"
resource "aws_iam_policy" "sns" {
  name        = "${var.name}-sns"
  description = "Publish to the SNS topic."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = var.sns_topic_arn
      }
    ]
  })

  tags = { Name = "${var.name}-sns" }
}

resource "aws_iam_role_policy_attachment" "sns" {
  role       = aws_iam_role.ec2.name
  policy_arn = aws_iam_policy.sns.arn
}
```

Add the topic ARN to `terraform/full-stack/outputs.tf`:

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

Publish directly to the topic:

=== "Linux / macOS"

    ```shell
    TOPIC_ARN=$(terraform output -raw sns_topic_arn)
    QUEUE_URL=$(terraform output -raw sqs_queue_url)

    aws sns publish \
      --topic-arn "$TOPIC_ARN" \
      --message "hello via SNS"
    ```

=== "Windows (PowerShell)"

    ```powershell
    $topicArn = terraform output -raw sns_topic_arn
    $queueUrl = terraform output -raw sqs_queue_url

    aws sns publish `
      --topic-arn $topicArn `
      --message "hello via SNS"
    ```

Now receive from the queue — the message arrived via SNS:

=== "Linux / macOS"

    ```shell
    aws sqs receive-message --queue-url "$QUEUE_URL"
    ```

=== "Windows (PowerShell)"

    ```powershell
    aws sqs receive-message --queue-url $queueUrl
    ```

!!! note "SNS wraps the message"
    The SQS message body won't be exactly `"hello via SNS"` — SNS wraps it in a JSON envelope
    with metadata fields (`Type`, `MessageId`, `TopicArn`, `Message`, `Timestamp`, ...). The
    original payload is under the `"Message"` key. The app needs to unwrap this when reading from
    a topic-subscribed queue.

### Connecting the app

One change in the publisher: switch from `SqsClient.sendMessage` to `SnsClient.publish`. The
consumer is unchanged.

```java title="TodoCreatedListener.java — publish to SNS"
SnsClient snsClient = SnsClient.builder()
    .region(Region.EU_WEST_1)
    .build();

snsClient.publish(builder -> builder
    .topicArn(TOPIC_ARN)   // from terraform output sns_topic_arn
    .message(todo.title())
    .build());
```

The queue consumer still reads from SQS. It doesn't know — or care — whether the message came
from a direct `SendMessage` or via an SNS topic. That independence is the point.

---

## Clean up

All messaging resources are destroyed with the rest of the stack:

```shell
terraform destroy
```

---

## Key takeaways

- SQS is pull-based: the consumer polls. SNS is push-based: it delivers immediately to all
  subscribers. They solve different problems and are often used together.
- SQS guarantees at-least-once delivery via the visibility timeout — a message reappears if the
  consumer doesn't delete it within the window. **Always delete after processing.**
- The dead-letter queue catches messages that repeatedly fail; it's where you look when something
  is broken, not a normal processing path.
- SNS → SQS gives durable fan-out: publish once, SNS delivers to every subscribed queue, each
  queue holds the message until its consumer is ready. Adding a second consumer later requires no
  change to the publisher.
- The SQS queue policy must explicitly allow SNS to write to it. Without it, SNS silently drops
  messages. Scope the permission with `aws:SourceArn` so only your topic can write to your queue.
- SNS wraps messages in a JSON envelope when delivering to SQS — the consumer needs to unwrap it
  to get the original payload.
