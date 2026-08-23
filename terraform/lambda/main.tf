# --------------------------------------------------------------------------
# Package function code into zip archives at plan time.
# Terraform recomputes source_code_hash whenever the .py file changes,
# so a code edit triggers a new deployment automatically.
# --------------------------------------------------------------------------

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

# --------------------------------------------------------------------------
# CloudWatch log groups
# Create them explicitly so we can set a retention period. Lambda creates
# its log group on first invocation if one doesn't exist, but without a
# retention policy — logs would accumulate forever.
# --------------------------------------------------------------------------

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

# --------------------------------------------------------------------------
# Producer: IAM execution role
# --------------------------------------------------------------------------

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

# --------------------------------------------------------------------------
# Producer: Lambda function
# --------------------------------------------------------------------------

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

  # Ensure the log group exists before the function is created — otherwise
  # Lambda auto-creates one with no retention policy on the first invocation.
  depends_on = [aws_cloudwatch_log_group.producer]

  tags = { Name = "${var.name}-producer" }
}

# --------------------------------------------------------------------------
# Producer: EventBridge schedule (every 1 minute)
# --------------------------------------------------------------------------

resource "aws_cloudwatch_event_rule" "schedule" {
  name                = "${var.name}-producer-schedule"
  description         = "Triggers ${var.name}-producer every minute."
  schedule_expression = "rate(1 minute)"

  tags = { Name = "${var.name}-producer-schedule" }
}

resource "aws_cloudwatch_event_target" "producer" {
  rule = aws_cloudwatch_event_rule.schedule.name
  arn  = aws_lambda_function.producer.arn
}

# Lambda requires an explicit resource-based policy to allow EventBridge
# to invoke it — IAM roles alone are not enough for cross-service triggers.
resource "aws_lambda_permission" "eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.producer.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.schedule.arn
}

# --------------------------------------------------------------------------
# Consumer: IAM execution role
# AWSLambdaSQSQueueExecutionRole is an AWS-managed policy that bundles
# CloudWatch Logs write access + the SQS permissions Lambda needs to poll
# and delete messages on your behalf (ReceiveMessage, DeleteMessage,
# GetQueueAttributes, ChangeMessageVisibility).
# --------------------------------------------------------------------------

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

# --------------------------------------------------------------------------
# Consumer: Lambda function
# --------------------------------------------------------------------------

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

# --------------------------------------------------------------------------
# Consumer: SQS event source mapping
# Lambda polls the queue and invokes the function with a batch of messages.
# Lambda handles the polling loop — no Scheduled annotation needed.
# --------------------------------------------------------------------------

resource "aws_lambda_event_source_mapping" "sqs" {
  event_source_arn = var.sqs_queue_arn
  function_name    = aws_lambda_function.consumer.arn
  batch_size       = 10
  enabled          = true
}
