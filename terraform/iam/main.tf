resource "aws_iam_role" "ec2" {
  name = "${var.name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.name}-ec2-role"
  }
}

resource "aws_iam_policy" "s3_read" {
  name        = "${var.name}-s3-read"
  description = "Read-only access to the ${var.bucket_name} S3 bucket."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket",
        ]
        Resource = [
          "arn:aws:s3:::${var.bucket_name}",
          "arn:aws:s3:::${var.bucket_name}/*",
        ]
      }
    ]
  })

  tags = {
    Name = "${var.name}-s3-read"
  }
}

resource "aws_iam_role_policy_attachment" "s3_read" {
  role       = aws_iam_role.ec2.name
  policy_arn = aws_iam_policy.s3_read.arn
}

resource "aws_iam_policy" "dynamodb" {
  name        = "${var.name}-dynamodb"
  description = "Read/write access to the ${var.dynamodb_table_arn} DynamoDB table."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan",
        ]
        Resource = var.dynamodb_table_arn
      }
    ]
  })

  tags = {
    Name = "${var.name}-dynamodb"
  }
}

resource "aws_iam_role_policy_attachment" "dynamodb" {
  role       = aws_iam_role.ec2.name
  policy_arn = aws_iam_policy.dynamodb.arn
}

# resource "aws_iam_policy" "sqs" { ... }        # added in checkpoint/06-messaging
# resource "aws_iam_role_policy_attachment" "sqs" { ... }
# resource "aws_iam_policy" "sns" { ... }
# resource "aws_iam_role_policy_attachment" "sns" { ... }

resource "aws_iam_instance_profile" "ec2" {
  name = "${var.name}-ec2-profile"
  role = aws_iam_role.ec2.name

  tags = {
    Name = "${var.name}-ec2-profile"
  }
}
