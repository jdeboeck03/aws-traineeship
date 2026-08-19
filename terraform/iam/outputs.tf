output "instance_profile_name" {
  description = "Name of the IAM instance profile to attach to the EC2 instance."
  value       = aws_iam_instance_profile.ec2.name
}
