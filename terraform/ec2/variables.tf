variable "name" {
  description = "Unique name used to tag and name all resources (e.g. your first name)."
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
  description = "Amazon Machine Image ID. Defaults to Amazon Linux 2023 in eu-west-1."
  type        = string
  default     = "ami-089950bc622d39ed8"
}
