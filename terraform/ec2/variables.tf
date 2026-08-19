variable "name" {
  description = "Unique name used to tag and name all resources (e.g. your first name)."
  type        = string
}

variable "owner" {
  description = "Your identity for the Owner tag, e.g. firstname.lastname."
  type        = string
}

variable "contact" {
  description = "Your email address for the Contact tag."
  type        = string
}

variable "project" {
  description = "Project you are working on"
  type        = string
}

variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "eu-west-1"
}

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
  default     = "t3.micro"
}

variable "subnet_id" {
  description = "Subnet to launch the instance in. If null, AWS picks a subnet in the default VPC."
  type        = string
  default     = null
}

variable "security_group_ids" {
  description = "Security group IDs to attach. If empty, a new SSH-allowing group is created in the default VPC."
  type        = list(string)
  default     = []
}

variable "iam_instance_profile" {
  description = "Name of the IAM instance profile to attach. If null, the instance runs without a profile."
  type        = string
  default     = null
}
