output "vpc_id" {
  description = "ID of the VPC."
  value       = module.vpc.vpc_id
}

output "public_subnet_id" {
  description = "ID of the public subnet."
  value       = module.vpc.public_subnet_id
}

output "ssh_security_group_id" {
  description = "ID of the SSH security group."
  value       = aws_security_group.ssh.id
}

output "instance_id" {
  description = "EC2 instance ID."
  value       = module.ec2.instance_id
}

output "public_ip" {
  description = "Public IP address of the EC2 instance."
  value       = module.ec2.public_ip
}

output "ssh_command" {
  description = "Ready-to-run SSH command."
  value       = module.ec2.ssh_command
}

output "website_endpoint" {
  description = "HTTP endpoint for the S3 static website."
  value       = module.s3.website_endpoint
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table."
  value       = module.dynamodb.table_name
}

output "sqs_queue_url" {
  description = "URL of the SQS queue."
  value       = module.sqs.queue_url
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic."
  value       = module.sns.topic_arn
}

output "ecr_repository_url" {
  description = "ECR repository URL (use this in docker tag/push commands)."
  value       = module.ecr.repository_url
}

output "alb_dns_name" {
  description = "URL of the Application Load Balancer."
  value       = module.ecs.alb_dns_name
}

output "producer_function_name" {
  description = "Name of the scheduled producer Lambda function."
  value       = module.lambda.producer_function_name
}

output "consumer_function_name" {
  description = "Name of the SQS consumer Lambda function."
  value       = module.lambda.consumer_function_name
}
