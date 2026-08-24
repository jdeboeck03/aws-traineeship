# Messaging — SQS and SNS

We are going to talk about 2 important AWS messaging services: queues and topics.

## SQS vs SNS at a glance

| | SQS | SNS |
|---|---|---|
| Model | Queue (point-to-point) | Topic (pub/sub) |
| Delivery | Pull — consumer polls | Push — SNS delivers immediately |
| Consumers | One per message | All subscribers simultaneously |
| Message retention | Yes — waits until consumed | No — deliver or drop |
| Good for | Task queues, work distribution | Broadcasting, fan-out |

---

## Amazon Simple Queue Service (SQS)

[Amazon Simple Queue Service (SQS)](https://aws.amazon.com/sqs/) is a fully managed message
queuing service. Messages are put on the queue using `sqs:SendMessage` and retrieved using
`sqs:ReceiveMessage`. After the client has processed the message, it is responsible for deleting
it — SQS never removes a message automatically after delivery. SQS guarantees at-least-once
delivery: if a message is not deleted within the visibility timeout, it is re-delivered. A
dead-letter queue (DLQ) catches messages that have been received too many times without being
deleted.

??? example "Now build it"
    Create an SQS queue (and a DLQ) in `terraform/full-stack/` using
    [`aws_sqs_queue`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue).
    In the app, use the AWS SDK to send a message when a todo is created (`TodoCreatedListener`)
    and to poll and delete messages on a schedule (`QueueConsumer`).

---

## Amazon Simple Notification Service (SNS)

[Amazon Simple Notification Service (SNS)](https://aws.amazon.com/sns/) is a fully managed
pub/sub messaging service. Messages are published to topics using `sns:Publish`. Subscribers
receive a copy of every message immediately — SNS pushes, it does not retain messages.
SNS supports several protocols: SQS, Lambda, HTTP/S, email, and SMS. Combining SNS with SQS
gives you durable fan-out: publish once to the topic and SNS delivers to every subscribed queue.

??? example "Now build it"
    Create an SNS topic using
    [`aws_sns_topic`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic)
    and subscribe your existing SQS queue to it using
    [`aws_sns_topic_subscription`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_subscription).
    You will also need an
    [`aws_sqs_queue_policy`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue_policy)
    to allow SNS to write to your queue.
    Change the app to publish to the topic instead of directly to the queue (`TodoCreatedListener`).
    The queue consumer stays unchanged.

    !!! note "SNS envelope"
        SNS wraps messages in a JSON envelope when delivering to SQS — the original payload is
        under the `"Message"` key. The app needs to unwrap this when reading from a
        topic-subscribed queue.
