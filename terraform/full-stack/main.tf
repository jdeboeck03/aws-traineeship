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

resource "aws_security_group" "ssh" {
  name        = "${var.name}-ssh-sg"
  description = "Allow SSH inbound"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name}-ssh-sg"
  }
}

module "ec2" {
  source             = "../ec2"
  name               = var.name
  owner              = var.owner
  contact            = var.contact
  project            = var.project
  region             = var.region
  subnet_id          = module.vpc.public_subnet_id
  security_group_ids = [aws_security_group.ssh.id]
}

module "s3" {
  source      = "../s3"
  bucket_name = var.bucket_name
}
