variable "name" {
  description = "Unique name used as a prefix for all resource Name tags."
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
  description = "Project you are working on."
  type        = string
}

variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "eu-west-1"
}

variable "bucket_name" {
  description = "Globally unique S3 bucket name, e.g. <your-name>-traineeship-site."
  type        = string
}
