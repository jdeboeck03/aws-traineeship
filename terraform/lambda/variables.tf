variable "name" {
  description = "Prefix used for all resource names."
  type        = string
}

variable "sns_topic_arn" {
  description = "ARN of the SNS topic the producer Lambda publishes to."
  type        = string
}

variable "sqs_queue_arn" {
  description = "ARN of the SQS queue the consumer Lambda reads from (event source mapping)."
  type        = string
}
