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

# AWS publishes the current recommended Amazon Linux 2023 build under this SSM parameter, so we
# never have to hardcode an AMI ID that goes stale as new builds ship every few weeks.
data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

locals {
  # SSM parameter values are marked sensitive by default even though this one (a public AMI ID)
  # isn't a secret — unmark it so it's still visible in plan/apply output.
  ami_id = coalesce(var.ami_id, nonsensitive(data.aws_ssm_parameter.al2023_ami.value))
}

# Generate an SSH key pair locally and upload the public key to AWS.
resource "tls_private_key" "this" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "this" {
  key_name   = "${var.name}-key"
  public_key = tls_private_key.this.public_key_openssh
}

# Save the private key to disk so you can SSH in.
resource "local_sensitive_file" "private_key" {
  filename        = "${var.name}-key.pem"
  content         = tls_private_key.this.private_key_pem
  file_permission = "0400"
}

# Security group: allow SSH inbound, all outbound.
resource "aws_security_group" "this" {
  name        = "${var.name}-sg"
  description = "Allow SSH inbound"

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
    Name = "${var.name}-sg"
  }
}

resource "aws_instance" "this" {
  ami                         = local.ami_id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.this.key_name
  vpc_security_group_ids      = [aws_security_group.this.id]
  associate_public_ip_address = true

  tags = {
    Name = var.name
  }
}
