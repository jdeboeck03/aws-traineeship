terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region  = var.region
  profile = "traineeship"

  default_tags {
    tags = {
      Project = var.project
      Owner   = var.owner
      Contact = var.contact
    }
  }
}

module "vpc" {
  source  = "../vpc"
  name    = var.name
  owner   = var.owner
  contact = var.contact
  project = var.project
  region  = var.region
}

module "ec2" {
  source             = "../ec2"
  name               = var.name
  owner              = var.owner
  contact            = var.contact
  project            = var.project
  region             = var.region
  subnet_id          = module.vpc.public_subnet_id
  security_group_ids = [module.vpc.ssh_security_group_id]
}
