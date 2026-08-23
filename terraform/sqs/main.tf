resource "aws_sqs_queue" "dlq" {
  name                       = "${var.name}-dlq"
  message_retention_seconds  = 1209600 # 14 days — long enough to inspect failed messages

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
