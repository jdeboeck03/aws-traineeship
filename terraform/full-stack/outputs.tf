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
