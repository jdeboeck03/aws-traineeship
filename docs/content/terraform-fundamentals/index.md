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

## Terraform Registry

Every provider and its resources are documented on the
[Terraform Registry](https://registry.terraform.io). For the AWS provider, the docs live at:

```
registry.terraform.io/providers/hashicorp/aws/latest/docs
```

The left-hand sidebar splits into **Resources** (things Terraform creates and manages) and **Data
Sources** (things Terraform reads from AWS without creating). When you need to know what arguments
a resource accepts or what attributes it exposes, this is the first place to look.

For example, searching for `aws_instance` takes you straight to the EC2 instance resource page,
which lists every argument (`ami`, `instance_type`, `vpc_security_group_ids`, ...) with its type,
whether it's required or optional, and what the resource exports after creation (`public_ip`,
`id`, ...).

!!! tip
    The quickest path is usually a web search for `terraform aws_instance` or whichever resource
    type you need — the Registry page is almost always the top result.

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

## Providing variable values

`-var="key=value"` works, but it gets unwieldy once a module has several required variables — as
`terraform/ec2` now does (`name`, `owner`, `contact`, `project`). Terraform accepts values from a
few places, in increasing order of precedence:

1. A `terraform.tfvars` file in the module directory — loaded **automatically** by every `plan`,
   `apply`, and `destroy`. Any `*.auto.tfvars` file is loaded the same way. No flag needed.
2. `-var-file=<name>.tfvars` — for any other filename; Terraform only reads it if you point at it.
3. `TF_VAR_<name>` environment variables.
4. `-var="key=value"` flags — highest precedence, good for one-off overrides.

The practical pattern for this repo: create your own `terraform.tfvars` once per module (it's
git-ignored — see `.gitignore` — so nothing personal gets committed), then run bare `terraform
plan` / `apply` / `destroy` from then on:

```hcl
# terraform/<module>/terraform.tfvars — not committed
name    = "<your-name>"
owner   = "<your-name>.<your-lastname>"
contact = "<you>@axxes.com"
project = "SDT-Traineeship"
```

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
- A git-ignored `terraform.tfvars` per module beats repeating `-var=...` flags on every command.
- The [Terraform Registry](https://registry.terraform.io/providers/hashicorp/aws/latest/docs) is
  the reference for every resource and data source argument — search for the type name when you
  need to know what a resource accepts or exports.
