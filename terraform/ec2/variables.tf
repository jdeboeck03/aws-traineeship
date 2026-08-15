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

variable "ami_id" {
  description = "Amazon Machine Image ID. Defaults to the latest Amazon Linux 2023 AMI for the target region — override only if you need a specific build."
  type        = string
  default     = null
}
