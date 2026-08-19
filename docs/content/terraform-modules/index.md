# Terraform Modules

So far, each `terraform/<module>/` directory has been a self-contained unit: its own provider, its
own resources, its own state, applied and destroyed on its own. That works for a single service in
isolation, but real infrastructure needs services to talk to each other — an EC2 instance should
live in a subnet, which lives in a VPC you control, not the account's default one.

Terraform's answer is **module composition**: one root module calls other modules as children,
wiring their outputs into each other's inputs. In this section you'll refactor the standalone `vpc`
and `ec2` modules from the last two lessons into child modules, and build a `full-stack` root that
composes them — the same root every later module in this course gets added to.

## Concepts

**Root module vs. child module**
Any directory with `.tf` files is a module. When you run `terraform apply` you are in the *root*
module — the entry point Terraform starts from. A *child* module is any module the root (or another
module) calls with a `module` block. The distinction is positional: the same `vpc/` directory was a
standalone root when you `cd`'d into it in the Networking lesson, and is about to become a child
when called from `full-stack/`.

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
don't add a `provider` block inside `vpc/` or `ec2/` when they're called as children. A leftover
`provider` block in a child module isn't just redundant: it creates a second, independent provider
instance that could silently diverge from the root's region, profile, or `default_tags`. That's why
step 1 below deletes them rather than leaving them in place.

**Resources that span modules belong in the root**
The SSH security group you're about to add needs the VPC's ID (an output only available *after*
calling `module.vpc`) and feeds into the EC2 module as an input. It doesn't belong inside `vpc/`
(which shouldn't know about EC2) or `ec2/` (which shouldn't know about VPC) — it belongs in the
root, the only place that sees both.

**State and destroy order**
All resources created by the root and its children live in one state file. `terraform destroy`
removes them in the correct dependency order automatically — this is the practical payoff: from
here on, one command tears down everything built across every module so far, no matter how many
child modules have accumulated.

---

## Refactoring into a full-stack root

!!! warning "Destroy the standalone stacks first"
    Once you remove the `provider` blocks in step 1, `terraform/vpc/` and `terraform/ec2/` can no
    longer be applied or destroyed on their own. Make sure you've run `terraform destroy` in both
    directories first (see each module's own Clean Up section) — otherwise their resources are
    orphaned with no state pointing at them until you temporarily restore the provider block to
    destroy them.
    ```shell
    cd terraform/ec2
    terraform destroy
    cd ../vpc
    terraform destroy
    ```

### Step 1 — Strip the provider blocks

Delete the `terraform { required_providers { ... } }` and `provider "aws" { ... }` blocks from the
top of both `terraform/vpc/main.tf` and `terraform/ec2/main.tf`. Everything below those blocks
(the resources, data sources) stays exactly as it was.

### Step 2 — Let the EC2 module accept an external subnet and security group

Right now `terraform/ec2/` always creates its own security group and always launches into the
default VPC. To compose it with the `vpc` module, it needs to accept those as optional inputs.

Add two variables to `terraform/ec2/variables.tf`:

```hcl
variable "subnet_id" {
  description = "Subnet to launch the instance in. If null, AWS picks a subnet in the default VPC."
  type        = string
  default     = null
}

variable "security_group_ids" {
  description = "Security group IDs to attach. If empty, a new SSH-allowing group is created in the default VPC."
  type        = list(string)
  default     = []
}
```

Update `terraform/ec2/main.tf` so the security group is only created when none are passed in, and
the instance uses whichever subnet/security groups it was given:

```hcl
# Only create a security group when none are passed in — allows standalone use without a VPC module.
resource "aws_security_group" "this" {
  count       = length(var.security_group_ids) == 0 ? 1 : 0
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
  ami                         = nonsensitive(data.aws_ssm_parameter.al2023_ami.value)
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.this.key_name
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = length(var.security_group_ids) > 0 ? var.security_group_ids : [aws_security_group.this[0].id]
  associate_public_ip_address = true

  tags = {
    Name = var.name
  }
}
```

The `count = length(var.security_group_ids) == 0 ? 1 : 0` trick is how a resource becomes
conditional in Terraform — `count` of `0` means the resource isn't created at all. The instance's
`vpc_security_group_ids` then picks whichever list is non-empty. `terraform/vpc/` needs no
equivalent change — it has no inputs that depend on another module.

### Step 3 — Build `terraform/full-stack/`

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

The `tls` and `local` providers are declared here even though only the `ec2` module uses them
directly — a root module must declare every provider any of its children need.

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

### Apply

```shell
cd terraform/full-stack

terraform init
terraform plan
terraform apply
```

After apply, Terraform prints the public IP and the ready-to-run SSH command. The key pair was
written to `terraform/full-stack/<your-name>-key.pem` — that's the directory you ran `apply` from,
distinct from the (now-destroyed) key pair the standalone EC2 module created earlier.

```shell
chmod 400 <your-name>-key.pem
ssh -i <your-name>-key.pem ec2-user@<public-ip>
```

Check the instance's subnet in the EC2 console, or via
`aws ec2 describe-instances --instance-ids <instance-id> --query 'Reservations[0].Instances[0].SubnetId'`
— it should match the `public_subnet_id` output, confirming the instance is running inside your VPC
rather than the account's default one.

### Clean up

```shell
terraform destroy
```

From here on, every module added to this course gets wired into `terraform/full-stack/` and torn
down with this same command — you won't `cd` into `terraform/vpc/` or `terraform/ec2/` again.

---

## Key takeaways

- A root module calls child modules with `module` blocks; child module outputs are referenced as
  `module.<name>.<output>`.
- Declare the provider once in the root — child modules inherit it automatically. A leftover
  `provider` block in a child risks a second, divergent provider instance, not just redundancy.
- Run `terraform init` after adding a `module` block to register the new source path.
- Making a resource conditional in Terraform is done with `count = <condition> ? 1 : 0` — a count
  of `0` means the resource isn't created.
- All state lives in one file at the root level; `terraform destroy` handles teardown order across
  every child module, no matter how many have accumulated.
- Resources that span modules — needing one module's output as another's input — are defined in the
  root, not inside either child. This keeps each child module focused and independently reusable.
