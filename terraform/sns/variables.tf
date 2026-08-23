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
