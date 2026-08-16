# Networking — VPC

Every resource you launch on AWS lives inside a **Virtual Private Cloud (VPC)** — an isolated
virtual network you control. Understanding VPCs is foundational: ECS tasks, Lambda functions, and
databases all sit inside one, and the public/private split determines what can reach the internet
and what can't.

## Concepts

**VPC**
An isolated virtual network within a single AWS region. You define its IP address range (the CIDR
block) and control all routing and access rules inside it. Each AWS account comes with a
ready-to-use *default VPC* in every region — useful for quick experiments, but you should create
your own for any real workload so your resources are isolated from other accounts' defaults.

**CIDR block**
Classless Inter-Domain Routing notation — a compact way to express an IP address range.
`10.0.0.0/16` means the 65,536 addresses from `10.0.0.0` to `10.0.255.255`. The `/16` is the
prefix length: smaller numbers mean more addresses. A VPC typically uses a `/16`; subnets carve it
into smaller `/24` (256-address) slices.

**Subnet**
A subdivision of the VPC's address range, scoped to a single **Availability Zone** (AZ). A subnet
in `eu-west-1a` can only hold resources in that data centre. You choose the CIDR block for each
subnet — it must be a subset of the VPC's block and can't overlap with other subnets.

**Public vs. private subnet**
The distinction is purely about routing, not a flag you set:

- A **public subnet** has a route that sends internet-bound traffic (`0.0.0.0/0`) to an **Internet
  Gateway**. Resources in it can be assigned a public IP and are reachable from the internet.
- A **private subnet** has no such route. Resources in it have no direct path to or from the
  internet — they can only talk to other resources inside the VPC (or via a NAT Gateway).

**Internet Gateway (IGW)**
A horizontally scaled, redundant gateway that connects a VPC to the public internet. You attach one
to the VPC, then add a route in a route table pointing to it — that's what makes a subnet public.

**Route table**
A set of routing rules that determine where network traffic from a subnet goes. Every subnet is
associated with exactly one route table. AWS adds a *local* route automatically (traffic within the
VPC stays in the VPC); you add additional routes for internet or NAT access.

**Availability Zone**
An isolated data centre location within a region. `eu-west-1` has three: `eu-west-1a`,
`eu-west-1b`, `eu-west-1c`. Spreading resources across AZs gives fault tolerance — if one AZ goes
down, the others keep running. Each subnet lives in exactly one AZ.

**NAT Gateway**
Lets resources in a *private* subnet reach the internet (e.g. to download packages) without
exposing them to inbound connections. Not free — billed per hour and per GB of data processed. Out
of scope for these exercises but worth knowing it exists.

---

!!! info "No manual exercise for this module"
    From VPC onwards, modules go straight to Terraform. VPC resources (subnets, route tables,
    internet gateways, associations) are networking wiring — creating them by hand doesn't build
    intuition beyond what the concepts section already covers, and the manual cleanup order is
    error-prone. Terraform also produces the VPC ID and subnet ID as outputs, which later modules
    consume directly.

    EC2 is the exception: launching an instance manually first makes AMIs, key pairs, and security
    groups concrete before Terraform abstracts them away.

## Exercise — Provision with Terraform

See [Terraform Fundamentals](../terraform-fundamentals/index.md) if you haven't used Terraform yet
or need a refresher.

### Your task

Build a Terraform module in `terraform/vpc/` that creates a functional public VPC. Follow the same
layout as previous modules: `main.tf`, `variables.tf`, `outputs.tf`.

It should:

- Create a VPC with CIDR `10.0.0.0/16` and DNS hostnames enabled
- Create one public subnet (`10.0.1.0/24`) in `eu-west-1a` that auto-assigns public IPs
- Create an internet gateway and attach it to the VPC
- Create a route table with a default route (`0.0.0.0/0`) to the internet gateway, and associate
  it with the public subnet
- Create a security group inside the VPC that allows inbound SSH (port 22)
- Tag every resource with `Project`, `Owner`, `Contact` (via `default_tags`) plus a `Name` tag
- Take `name`, `owner`, `contact`, and `project` as required variables
- Output the VPC ID, the public subnet ID, and the SSH security group ID — Exercise 2 will use all three

??? question "Hints"
    - All resources in this module come from the `aws` provider — no additional providers needed.
    - Create the VPC first; the subnet, IGW, route table, and security group all need
      `vpc_id = aws_vpc.this.id`.
    - Look up `aws_vpc`, `aws_subnet`, `aws_internet_gateway`, `aws_route_table`,
      `aws_route_table_association`, and `aws_security_group` in the
      [Terraform Registry](https://registry.terraform.io/providers/hashicorp/aws/latest/docs).
    - The IGW needs to be *attached* to the VPC — check which resource handles attachment vs. which
      just creates the gateway.
    - The route table alone isn't enough — you also need to *associate* it with the subnet. There's
      a separate resource for that.
    - `enable_dns_hostnames = true` on the VPC is required for resources to get public DNS names.
    - `map_public_ip_on_launch = true` on the subnet is what makes instances in it get a public IP
      automatically — without it, instances are public-subnet-routable but have no IP.

??? example "Show solution"
    ```
    terraform/vpc/
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

    resource "aws_vpc" "this" {
      cidr_block           = var.vpc_cidr
      enable_dns_support   = true
      enable_dns_hostnames = true

      tags = {
        Name = "${var.name}-vpc"
      }
    }

    resource "aws_subnet" "public" {
      vpc_id                  = aws_vpc.this.id
      cidr_block              = var.public_subnet_cidr
      availability_zone       = "${var.region}a"
      map_public_ip_on_launch = true

      tags = {
        Name = "${var.name}-public-subnet"
      }
    }

    resource "aws_internet_gateway" "this" {
      vpc_id = aws_vpc.this.id

      tags = {
        Name = "${var.name}-igw"
      }
    }

    resource "aws_route_table" "public" {
      vpc_id = aws_vpc.this.id

      route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.this.id
      }

      tags = {
        Name = "${var.name}-public-rt"
      }
    }

    resource "aws_route_table_association" "public" {
      subnet_id      = aws_subnet.public.id
      route_table_id = aws_route_table.public.id
    }

    resource "aws_security_group" "ssh" {
      name        = "${var.name}-ssh-sg"
      description = "Allow SSH inbound"
      vpc_id      = aws_vpc.this.id

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

    variable "vpc_cidr" {
      description = "CIDR block for the VPC."
      type        = string
      default     = "10.0.0.0/16"
    }

    variable "public_subnet_cidr" {
      description = "CIDR block for the public subnet."
      type        = string
      default     = "10.0.1.0/24"
    }
    ```

    ```hcl title="outputs.tf"
    output "vpc_id" {
      description = "ID of the VPC."
      value       = aws_vpc.this.id
    }

    output "public_subnet_id" {
      description = "ID of the public subnet."
      value       = aws_subnet.public.id
    }

    output "ssh_security_group_id" {
      description = "ID of the SSH security group (allows inbound port 22)."
      value       = aws_security_group.ssh.id
    }
    ```

### Set your variables

Create a `terraform.tfvars` in `terraform/vpc/` (git-ignored, so nothing personal gets committed):

```hcl
# terraform/vpc/terraform.tfvars — not committed
name    = "<your-name>"
owner   = "<your-name>.<your-lastname>"
contact = "<you>@axxes.com"
project = "SDT-Traineeship"
```

### Initialise and apply

```shell
cd terraform/vpc

terraform init
terraform plan
terraform apply
```

Terraform will print the VPC ID, subnet ID, and security group ID after apply.

### Clean up

```shell
terraform destroy
```

Terraform removes all resources in the correct dependency order automatically.

---

## Exercise 2 — Compose VPC and EC2 with Terraform modules

See [Calling modules](../terraform-fundamentals/index.md#calling-modules) in Terraform Fundamentals
if you haven't read it yet.

So far the VPC and EC2 modules are independent: each creates its own resources in isolation. In
practice, an EC2 instance belongs inside a VPC — launched into one of its subnets and protected by
one of its security groups. Terraform's `module` block lets you wire the two together: the VPC
module's outputs become the EC2 module's inputs.

### Your task

Build a root module in `terraform/full-stack/` that composes the VPC and EC2 modules. It should:

- Call the `vpc` module and the `ec2` module from their existing directories
- Pass the VPC's public subnet ID into the EC2 module's `subnet_id`
- Pass the VPC's SSH security group ID into the EC2 module's `security_group_ids` — the EC2
  module should not create its own security group in this composition
- Take the same four required variables (`name`, `owner`, `contact`, `project`)
- Output the VPC ID, subnet ID, instance ID, public IP, and SSH command

??? question "Hints"
    - A `module` block needs a `source` argument pointing at the directory of the module to call,
      e.g. `source = "../vpc"`. Run `terraform init` after adding or changing a `module` block.
    - Pass variables to child modules as arguments inside the `module` block, just like resource
      arguments.
    - Reference a child module's output as `module.<name>.<output>` — e.g.
      `module.vpc.public_subnet_id`.
    - The root module needs its own `terraform {}` and `provider "aws" {}` blocks — child modules
      inherit the provider automatically, so don't duplicate it inside `vpc/` or `ec2/`.
    - The EC2 module skips creating its own security group when `security_group_ids` is non-empty —
      pass the VPC's SSH group and the EC2 module handles the rest.
    - To surface EC2 outputs from the root module, forward them: `value = module.ec2.public_ip`.

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

`terraform init` downloads providers and registers the child modules. The plan will show resources
from both modules — VPC networking first, then the EC2 instance that depends on it. After apply,
the SSH command is printed directly; copy-paste it to connect.

### Clean up

```shell
terraform destroy
```

Terraform works out the dependency order automatically — the EC2 instance is destroyed before the
VPC resources it depends on.

---

## Key takeaways

- A VPC is an isolated virtual network; every AWS resource you launch lives inside one.
- The public/private distinction is purely about routing — a public subnet has a route to an
  internet gateway, a private subnet doesn't.
- An internet gateway + route table association is the minimum needed to make a subnet public.
  Three separate resources in Terraform, all required.
- DNS hostnames on the VPC and `map_public_ip_on_launch` on the subnet together give instances a
  reachable public address — either one missing and you can't connect.
- Module composition wires outputs of one module directly into inputs of another — no copy-pasting
  of IDs, no hardcoding, and `terraform destroy` in the root cleans up everything in order.
- The VPC ID and subnet ID output here are the inputs ECS will consume in a later module.
