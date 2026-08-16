# Terraform Modules

So far, each `terraform/<module>/` directory has been a self-contained unit: one provider, its own
resources, its own state. That works fine for a single service in isolation, but real infrastructure
needs services to talk to each other — an EC2 instance must live in a subnet, which lives in a VPC.

Terraform's answer is **module composition**: one root module calls other modules as children,
wiring their outputs into each other's inputs.

## Concepts

**Root module vs. child module**
Any directory with `.tf` files is a module. When you run `terraform apply` you are in the *root*
module — the entry point Terraform starts from. A *child* module is any module the root (or another
module) calls with a `module` block. The distinction is positional: the same `vpc/` directory is a
standalone root when you `cd` into it, and a child when called from `full-stack/`.

**`module` block**
Declares a call to a child module and passes values to its variables:

```hcl
module "vpc" {
  source = "../vpc"       # path to the module directory

  name    = var.name
  owner   = var.owner
  contact = var.contact
  project = var.project
}
```

After adding or changing a `module` block you must run `terraform init` again so Terraform
registers the new source path.

**Referencing module outputs**
A child module's outputs are available in the root as `module.<name>.<output>`:

```hcl
module "ec2" {
  source    = "../ec2"
  subnet_id = module.vpc.public_subnet_id   # vpc output → ec2 input
}
```

This is how you wire services together without hardcoding IDs.

**Provider inheritance**
Declare the provider (`aws`) once in the root module. Child modules inherit it automatically — you
don't add a `provider` block inside `vpc/` or `ec2/` when they are called as children. (They may
still have one for standalone use; Terraform ignores it when the module is called from a root.)

**State and destroy order**
All resources created by the root and its children live in one state file. `terraform destroy`
removes them in the correct dependency order automatically.

---

## Exercise — Full-stack module

You have two working modules: `terraform/vpc/` and `terraform/ec2/`. In this exercise you'll build
a new root module, `terraform/full-stack/`, that calls both and wires them together so the EC2
instance lands in the VPC's public subnet.

### Your task

Create `terraform/full-stack/` with `main.tf`, `variables.tf`, and `outputs.tf`. It should:

- Call the `vpc` module and the `ec2` module
- Pass the standard variables (`name`, `owner`, `contact`, `project`, `region`) to both
- Create an SSH security group (port 22 open inbound) attached to the VPC the `vpc` module created
  — define this resource directly in the root `main.tf`
- Wire the VPC's public subnet ID into the EC2 module's `subnet_id` input
- Wire the SSH security group ID into the EC2 module's `security_group_ids` input
- Output the VPC ID, public subnet ID, SSH SG ID, instance ID, public IP, and SSH command

The EC2 module's `security_group_ids` variable (a `list(string)`, defaults to `[]`) skips creating
its own default security group when you provide values — that's the clean handoff point.

??? question "Hints"
    - `source = "../vpc"` and `source = "../ec2"` — one level up from `full-stack/`.
    - After writing the `module` blocks, run `terraform init` before `plan` — Terraform needs to
      register the new source paths.
    - The SSH security group needs `vpc_id = module.vpc.vpc_id` — the VPC module outputs this.
    - `aws_security_group` ingress/egress blocks: look up the resource in the
      [Terraform Registry](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group).
    - Child modules inherit the root's `provider` block — no second `provider "aws"` block needed
      inside `vpc/main.tf` or `ec2/main.tf` when called as children. (The `terraform {}` blocks
      and `provider {}` blocks already present in those files are harmless.)
    - Outputs from the ec2 module are available as `module.ec2.instance_id`, `module.ec2.public_ip`,
      `module.ec2.ssh_command` — check `terraform/ec2/outputs.tf` to see what's exported.
    - The `tls` and `local` providers declared in the ec2 module also need to be declared in the
      full-stack root (in `terraform {}` → `required_providers`).

??? example "Show solution"
    ```
    terraform/full-stack/
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
    ```

    ```hcl title="variables.tf"
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
    ```

    ```hcl title="outputs.tf"
    output "vpc_id" {
      description = "ID of the VPC."
      value       = module.vpc.vpc_id
    }

    output "public_subnet_id" {
      description = "ID of the public subnet."
      value       = module.vpc.public_subnet_id
    }

    output "ssh_security_group_id" {
      description = "ID of the SSH security group."
      value       = aws_security_group.ssh.id
    }

    output "instance_id" {
      description = "EC2 instance ID."
      value       = module.ec2.instance_id
    }

    output "public_ip" {
      description = "Public IP address of the EC2 instance."
      value       = module.ec2.public_ip
    }

    output "ssh_command" {
      description = "Ready-to-run SSH command."
      value       = module.ec2.ssh_command
    }
    ```

### Set your variables

Create a `terraform.tfvars` in `terraform/full-stack/` (git-ignored):

```hcl
# terraform/full-stack/terraform.tfvars — not committed
name    = "<your-name>"
owner   = "<your-name>.<your-lastname>"
contact = "<you>@axxes.com"
project = "SDT-Traineeship"
```

### Initialise and apply

```shell
cd terraform/full-stack

terraform init
terraform plan
terraform apply
```

After apply, Terraform prints the public IP and the ready-to-run SSH command. Use the key from
`terraform/ec2/` (it was written there by the EC2 module's provisioner):

=== "Linux / macOS"

    ```bash
    ssh -i ../ec2/<your-name>-key.pem ec2-user@<public-ip>
    ```

=== "Windows (PowerShell)"

    ```powershell
    ssh -i ..\ec2\<your-name>-key.pem ec2-user@<public-ip>
    ```

### Clean up

```shell
terraform destroy
```

Terraform tears down the EC2 instance, the SSH security group, and all VPC resources in dependency
order.

!!! warning "Key pair"
    The key pair in AWS and the `.pem` file in `terraform/ec2/` were created by the standalone EC2
    module. `terraform destroy` in `full-stack/` does **not** remove them — they are managed by the
    EC2 module's own state. If you no longer need the standalone state, run `terraform destroy`
    from `terraform/ec2/` as well. If the key pair name collides with a fresh `terraform apply`
    in `ec2/`, delete it first:

    ```shell
    cd terraform/ec2
    terraform destroy
    ```

---

## Key takeaways

- A root module calls child modules with `module` blocks; child module outputs are referenced as
  `module.<name>.<output>`.
- Declare the provider once in the root — child modules inherit it automatically.
- Run `terraform init` after adding a `module` block to register the new source path.
- All state lives in one file at the root level; `terraform destroy` handles teardown order.
- Resources that span modules (here: the SSH security group needs the VPC ID but feeds into EC2)
  are defined in the root module, not inside either child module — this keeps each child focused and
  reusable independently.
