resource "aws_sns_topic" "this" {
  name = "${var.name}-topic"

  tags = {
    Name = "${var.name}-topic"
  }
}

# Allow SNS to write to the SQS queue — without this policy, SNS delivery is silently rejected.
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
