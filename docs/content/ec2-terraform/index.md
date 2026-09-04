# EC2 — Provisioning with Terraform

You've launched an EC2 instance manually in [EC2](../ec2/index.md) and worked through
[Terraform Fundamentals](../terraform-fundamentals/index.md). Now let's reproduce that same setup
as code — one command to create everything, one to tear it all down cleanly.

This is the Terraform equivalent of [Exercise 1](../ec2/index.md#exercise-1--launch-an-instance-manually):
an EC2 instance you can SSH into, with its own security group, tagged per
[Tagging](../tagging/index.md), running the current Amazon Linux 2023 AMI without hardcoding an
AMI ID.

## `terraform/ec2/`

```
terraform/ec2/
├── main.tf
├── variables.tf
└── outputs.tf
```

```hcl title="main.tf"
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
  # SSM parameter values are marked sensitive by default — nonsensitive() unmarks it so the AMI ID
  # is still visible in plan/apply output.
  ami                         = nonsensitive(data.aws_ssm_parameter.al2023_ami.value)
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.this.key_name
  vpc_security_group_ids      = [aws_security_group.this.id]
  associate_public_ip_address = true

  tags = {
    Name = var.name
  }
}
```

The provider block sets `default_tags` so every resource this module creates is automatically
tagged with `Project`, `Owner`, and `Contact`. This includes the security group, which also gets a
`Name` tag — nothing ends up untagged, and `terraform destroy` removes the instance and its
security group together.

```hcl title="variables.tf"
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
  description = "Project you are working on."
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
```

```hcl title="outputs.tf"
output "public_ip" {
  description = "Public IP address of the EC2 instance."
  value       = aws_instance.this.public_ip
}

output "instance_id" {
  description = "EC2 instance ID."
  value       = aws_instance.this.id
}

output "ssh_command" {
  description = "Ready-to-run SSH command."
  value       = "ssh -i ${local_sensitive_file.private_key.filename} ec2-user@${aws_instance.this.public_ip}"
}
```

## Set your variables

`name`, `owner`, `contact`, and `project` are all required, with no defaults. Rather than repeating
four `-var=...` flags on every command, create a `terraform.tfvars` file in `terraform/ec2/` —
Terraform loads it automatically, and it's already git-ignored so nothing personal gets committed
(see [Terraform Fundamentals](../terraform-fundamentals/index.md#providing-variable-values)):

```hcl
# terraform/ec2/terraform.tfvars — not committed
name    = "<your-name>"
owner   = "<your-name>.<your-lastname>"
contact = "<you>@axxes.com"
project = "SDT-Traineeship"
```

## Initialise and apply

```shell
cd terraform/ec2

# Download the AWS, tls, and local providers
terraform init

# Preview what will be created
terraform plan

# Create the resources
terraform apply
```

!!! failure "Apply fails with a duplicate key pair error"
    ```
    Error: creating EC2 Key Pair (<your-name>-key): InvalidKeyPair.Duplicate: The keypair already exists
    ```
    This happens if you did Exercise 1 first and didn't delete its key pair — Terraform tries to
    create one with the same name (`<your-name>-key`) and AWS rejects the duplicate. Delete the
    leftover key pair, then re-run `terraform apply`:
    ```shell
    aws ec2 delete-key-pair --key-name <your-name>-key --region eu-west-1
    ```

Terraform will print the instance's **public IP** when it finishes.

```shell
# SSH in using the generated key
chmod 400 <your-name>-key.pem
ssh -i <your-name>-key.pem ec2-user@<printed-public-ip>
```

## Clean up

Always destroy resources when you are done to avoid unnecessary costs:

```shell
terraform destroy
```

!!! note "This module gets composed later"
    Right now `terraform/ec2/` stands entirely on its own, provider block and all. In
    [Terraform Modules](../terraform-modules/index.md) — taught after Networking — you'll refactor
    this same module to be called from a shared root alongside a VPC module, instead of managing
    its own provider and state. Nothing you build here is wasted; it's the starting point for that
    refactor.

---

## Key takeaways

- Terraform reproduces the same setup as Exercise 1 — instance, security group, key pair — but
  creates and destroys them together in a single command.
- `default_tags` on the provider means every resource is tagged automatically; no separate tagging
  step needed for the security group the way there was in the console.
- `terraform destroy` removes everything Terraform created — no leftover security groups or key
  pairs to hunt down manually.
- Right now `terraform/ec2/` manages its own provider and state; in
  [Terraform Modules](../terraform-modules/index.md) you'll refactor it to be called from a shared
  root module alongside a VPC module.
