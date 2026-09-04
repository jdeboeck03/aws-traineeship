output "bucket_name" {
  description = "Name of the S3 bucket."
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "ARN of the S3 bucket."
  value       = aws_s3_bucket.this.arn
}

output "website_endpoint" {
  description = "HTTP endpoint for the static website."
  value       = "http://${aws_s3_bucket_website_configuration.this.website_endpoint}"
}
