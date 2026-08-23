output "repository_url" {
  description = "Full URL of the ECR repository (used in docker tag/push commands)."
  value       = aws_ecr_repository.this.repository_url
}

output "repository_name" {
  description = "Name of the ECR repository."
  value       = aws_ecr_repository.this.name
}
