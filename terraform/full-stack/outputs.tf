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
