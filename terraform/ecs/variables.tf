variable "name" {
  description = "Unique name used as a prefix for all ECS resource names."
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC to deploy into."
  type        = string
}

variable "subnet_ids" {
  description = "List of public subnet IDs for the ECS service and ALB (minimum 2, in different AZs)."
  type        = list(string)
}

variable "image_uri" {
  description = "Full ECR image URI including tag, e.g. 123456789.dkr.ecr.eu-west-1.amazonaws.com/your-name:latest."
  type        = string
}

variable "container_port" {
  description = "Port the container listens on."
  type        = number
  default     = 8080
}

variable "dynamodb_table_name" {
  description = "DynamoDB table name passed to the container as an environment variable."
  type        = string
}

variable "dynamodb_table_arn" {
  description = "ARN of the DynamoDB table, used to scope the task IAM policy."
  type        = string
}

variable "sqs_queue_url" {
  description = "SQS queue URL passed to the container as an environment variable."
  type        = string
}

variable "sqs_queue_arn" {
  description = "ARN of the SQS queue, used to scope the task IAM policy."
  type        = string
}

variable "sns_topic_arn" {
  description = "ARN of the SNS topic, passed to the container and used to scope the task IAM policy."
  type        = string
}

variable "s3_bucket_name" {
  description = "S3 bucket name passed to the container as an environment variable."
  type        = string
}

variable "s3_bucket_arn" {
  description = "ARN of the S3 bucket, used to scope the task IAM policy."
  type        = string
}
