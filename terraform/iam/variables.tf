variable "name" {
  description = "Unique name used as a prefix for all resource Name tags."
  type        = string
}

variable "bucket_name" {
  description = "Name of the S3 bucket the EC2 role is allowed to read."
  type        = string
}

variable "dynamodb_table_arn" {
  description = "ARN of the DynamoDB table the EC2 role is allowed to read and write."
  type        = string
}
