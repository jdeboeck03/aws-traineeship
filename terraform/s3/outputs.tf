output "bucket_name" {
  description = "Name of the S3 bucket."
  value       = aws_s3_bucket.this.id
}

output "website_endpoint" {
  description = "HTTP endpoint for the static website."
  value       = "http://${aws_s3_bucket_website_configuration.this.website_endpoint}"
}
