# Terraform Fundamentals

Every module in this traineeship is provisioned with **Terraform** instead of clicking through the
AWS console. This section covers the concepts and workflow you'll reuse in every module from here
on — EC2 is the first place you'll apply them.

## Why infrastructure as code

Clicking through the console works once, but it isn't repeatable, reviewable, or easy to tear
down cleanly. Terraform lets you describe the resources you want in files, so creating,
changing, and destroying infrastructure becomes a matter of running a command rather than
remembering which buttons you clicked.

## Installation

Install Terraform by following the
[official instructions](https://developer.hashicorp.com/terraform/install) for your operating
system, then verify it:

```shell
terraform -version
```

## Core concepts

**Provider**
A plugin that lets Terraform talk to a specific API — in this traineeship, the `aws` provider.
Declared once per root module, usually pinned to a version range:

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region  = var.region
  profile = "traineeship"
}
```

**Resource**
A single infrastructure object Terraform manages, such as an EC2 instance or a security group.
Each resource has a type (`aws_instance`) and a local name (`this`) used to refer to it elsewhere
in the module:

```hcl
resource "aws_instance" "this" {
  ami           = var.ami_id
  instance_type = var.instance_type
}
```

**Variable**
An input to a module, so the same code can be reused with different values (your name, region,
instance size, ...) instead of hardcoding them:

```hcl
variable "name" {
  description = "Unique name used to tag and name all resources."
  type        = string
}
```

**Output**
A value Terraform prints after `apply` — useful for things you need afterwards, like a public IP
or a generated ID:

```hcl
output "public_ip" {
  value = aws_instance.this.public_ip
}
```

**State**
Terraform keeps track of what it has already created in a state file (`terraform.tfstate`), so it
knows what to change or destroy on the next run. This file can contain sensitive values and is
specific to your own local run, so it's git-ignored in this repo (see `.gitignore`) — never commit
it, and never hand-edit it.

## Project layout

Every module in this repo follows the same layout, under `terraform/<module>/`:

```
terraform/<module>/
├── main.tf          # provider and resources
├── variables.tf     # input variables
└── outputs.tf       # useful values printed after apply
```

## The workflow

```shell
cd terraform/<module>

# Download the provider plugins
terraform init

# Preview what will be created/changed/destroyed
terraform plan -var="name=<your-name>"

# Apply the changes
terraform apply -var="name=<your-name>"

# Tear everything down again
terraform destroy -var="name=<your-name>"
```

Run `init` once per module (or whenever providers change), and always `plan` before `apply` so you
know what's about to happen. **Always `destroy` when you're done with an exercise** — this is a
shared account, and unused resources cost money.

## Tagging

Every provider block in this repo also sets `default_tags` so that everything you create is
automatically tagged with your identity — see [Tagging](../tagging/index.md) for the full
convention and why it's structured that way.

## Key takeaways

- Terraform describes infrastructure as code: repeatable, reviewable, and easy to tear down.
- `provider` → `resource` → `variable` → `output` are the four building blocks you'll see in every
  module.
- The state file tracks what exists; never commit or hand-edit it.
- Workflow is always `init` → `plan` → `apply`, and `destroy` when you're done.
