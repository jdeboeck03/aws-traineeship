output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "public_subnet_id" {
  description = "ID of the public subnet."
  value       = aws_subnet.public.id
}

output "ssh_security_group_id" {
  description = "ID of the SSH security group (allows inbound port 22)."
  value       = aws_security_group.ssh.id
}
