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

## Exercise 1 — Create a VPC manually

### Via the console

1. Open the [VPC console](https://eu-west-1.console.aws.amazon.com/vpc/home?region=eu-west-1#vpcs:)
   and click **Create VPC**.
2. Under **Resources to create** select **VPC and more** — this creates the VPC, subnets, internet
   gateway, and route tables in one step.
3. Set the **Name tag auto-generation** field to something unique, e.g. `<your-name>`. All created
   resources will be prefixed with this name.
4. Set **IPv4 CIDR block** to `10.0.0.0/16`.
5. Set **Number of Availability Zones** to `1`.
6. Set **Number of public subnets** to `1` and **Number of private subnets** to `0`.
7. Under **NAT gateways** select **None** (NAT Gateways cost money and aren't needed here).
8. Leave all other options at their defaults and click **Create VPC**.

!!! warning "The wizard creates several resources — tag them all"
    The **VPC and more** wizard creates a VPC, a subnet, an internet gateway, a route table, and a
    route table association in one shot. Only the VPC itself gets the `Name` tag from the
    auto-generation field — the other resources each get their own `Name` tag (e.g.
    `<your-name>-subnet-public1-eu-west-1a`) but **none** of them get `Project`, `Owner`, or
    `Contact` tags.

    After the wizard completes, go to each resource type in the VPC console and add the three
    required tags manually:

    - **VPCs** — select your VPC → **Tags** tab → **Manage tags**
    - **Subnets** — same flow
    - **Internet gateways** — same flow
    - **Route tables** — same flow

### Via the CLI

The CLI approach creates each resource explicitly, making the relationship between them visible.
Unlike the console wizard, nothing is created implicitly.

=== "Linux / macOS"

    ```shell
    # Create the VPC
    VPC_ID=$(aws ec2 create-vpc \
      --cidr-block 10.0.0.0/16 \
      --region eu-west-1 \
      --query 'Vpc.VpcId' --output text)

    # Enable DNS hostnames so instances get public DNS names
    aws ec2 modify-vpc-attribute \
      --vpc-id "$VPC_ID" --enable-dns-hostnames

    # Create a public subnet in eu-west-1a
    SUBNET_ID=$(aws ec2 create-subnet \
      --vpc-id "$VPC_ID" \
      --cidr-block 10.0.1.0/24 \
      --availability-zone eu-west-1a \
      --region eu-west-1 \
      --query 'Subnet.SubnetId' --output text)

    # Auto-assign public IPs to instances launched in this subnet
    aws ec2 modify-subnet-attribute \
      --subnet-id "$SUBNET_ID" --map-public-ip-on-launch

    # Create and attach an internet gateway
    IGW_ID=$(aws ec2 create-internet-gateway \
      --region eu-west-1 \
      --query 'InternetGateway.InternetGatewayId' --output text)

    aws ec2 attach-internet-gateway \
      --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID" --region eu-west-1

    # Create a route table and add a default route to the internet gateway
    RT_ID=$(aws ec2 create-route-table \
      --vpc-id "$VPC_ID" \
      --region eu-west-1 \
      --query 'RouteTable.RouteTableId' --output text)

    aws ec2 create-route \
      --route-table-id "$RT_ID" \
      --destination-cidr-block 0.0.0.0/0 \
      --gateway-id "$IGW_ID" \
      --region eu-west-1

    # Associate the route table with the subnet — this is what makes the subnet public
    aws ec2 associate-route-table \
      --route-table-id "$RT_ID" --subnet-id "$SUBNET_ID" --region eu-west-1
    ```

=== "Windows (PowerShell)"

    ```powershell
    # Create the VPC
    $VpcId = aws ec2 create-vpc `
      --cidr-block 10.0.0.0/16 `
      --region eu-west-1 `
      --query "Vpc.VpcId" --output text

    # Enable DNS hostnames so instances get public DNS names
    aws ec2 modify-vpc-attribute `
      --vpc-id $VpcId --enable-dns-hostnames

    # Create a public subnet in eu-west-1a
    $SubnetId = aws ec2 create-subnet `
      --vpc-id $VpcId `
      --cidr-block 10.0.1.0/24 `
      --availability-zone eu-west-1a `
      --region eu-west-1 `
      --query "Subnet.SubnetId" --output text

    # Auto-assign public IPs to instances launched in this subnet
    aws ec2 modify-subnet-attribute `
      --subnet-id $SubnetId --map-public-ip-on-launch

    # Create and attach an internet gateway
    $IgwId = aws ec2 create-internet-gateway `
      --region eu-west-1 `
      --query "InternetGateway.InternetGatewayId" --output text

    aws ec2 attach-internet-gateway `
      --internet-gateway-id $IgwId --vpc-id $VpcId --region eu-west-1

    # Create a route table and add a default route to the internet gateway
    $RtId = aws ec2 create-route-table `
      --vpc-id $VpcId `
      --region eu-west-1 `
      --query "RouteTable.RouteTableId" --output text

    aws ec2 create-route `
      --route-table-id $RtId `
      --destination-cidr-block 0.0.0.0/0 `
      --gateway-id $IgwId `
      --region eu-west-1

    # Associate the route table with the subnet — this is what makes the subnet public
    aws ec2 associate-route-table `
      --route-table-id $RtId --subnet-id $SubnetId --region eu-west-1
    ```

!!! note "Don't forget the tags"
    None of the resources above are tagged. Add `Project`, `Owner`, `Contact`, and `Name` tags to
    each one — see [Tagging](../tagging/index.md).

### Clean up

Deleting a VPC requires removing its dependencies first, in order:

=== "Linux / macOS"

    ```shell
    # Disassociate and delete the route table (the main route table can't be deleted)
    aws ec2 disassociate-route-table --association-id <assoc-id> --region eu-west-1
    aws ec2 delete-route-table --route-table-id <rt-id> --region eu-west-1

    # Detach and delete the internet gateway
    aws ec2 detach-internet-gateway \
      --internet-gateway-id <igw-id> --vpc-id <vpc-id> --region eu-west-1
    aws ec2 delete-internet-gateway --internet-gateway-id <igw-id> --region eu-west-1

    # Delete the subnet
    aws ec2 delete-subnet --subnet-id <subnet-id> --region eu-west-1

    # Delete the VPC
    aws ec2 delete-vpc --vpc-id <vpc-id> --region eu-west-1
    ```

=== "Windows (PowerShell)"

    ```powershell
    # Disassociate and delete the route table (the main route table can't be deleted)
    aws ec2 disassociate-route-table --association-id <assoc-id> --region eu-west-1
    aws ec2 delete-route-table --route-table-id <rt-id> --region eu-west-1

    # Detach and delete the internet gateway
    aws ec2 detach-internet-gateway `
      --internet-gateway-id <igw-id> --vpc-id <vpc-id> --region eu-west-1
    aws ec2 delete-internet-gateway --internet-gateway-id <igw-id> --region eu-west-1

    # Delete the subnet
    aws ec2 delete-subnet --subnet-id <subnet-id> --region eu-west-1

    # Delete the VPC
    aws ec2 delete-vpc --vpc-id <vpc-id> --region eu-west-1
    ```

!!! tip "Find resource IDs"
    If you've lost track of an ID, find it in the VPC console or with
    `aws ec2 describe-vpcs`, `aws ec2 describe-subnets`, etc. — filter by the `Name` tag or CIDR
    to find the right one.

---

## Exercise 2 — Provision with Terraform

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
- Tag every resource with `Project`, `Owner`, `Contact` (via `default_tags`) plus a `Name` tag
- Take `name`, `owner`, `contact`, and `project` as required variables
- Output the VPC ID and the public subnet ID — later modules will reference these

??? question "Hints"
    - All resources in this module come from the `aws` provider — no additional providers needed.
    - Create the VPC first; the subnet, IGW, and route table all need `vpc_id = aws_vpc.this.id`.
    - Look up `aws_vpc`, `aws_subnet`, `aws_internet_gateway`, `aws_route_table`, and
      `aws_route_table_association` in the
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

Terraform will print the VPC ID and subnet ID after apply — note them down, later modules will ask
for them.

### Clean up

```shell
terraform destroy
```

Terraform removes all five resources (VPC, subnet, IGW, route table, association) in the correct
dependency order automatically.

---

## Key takeaways

- A VPC is an isolated virtual network; every AWS resource you launch lives inside one.
- The public/private distinction is purely about routing — a public subnet has a route to an
  internet gateway, a private subnet doesn't.
- An internet gateway + route table association is the minimum needed to make a subnet public.
  Three separate resources in Terraform, all required.
- DNS hostnames on the VPC and `map_public_ip_on_launch` on the subnet together give instances a
  reachable public address — either one missing and you can't connect.
- `terraform destroy` removes everything in dependency order; the manual cleanup order (association
  → route table → IGW → subnet → VPC) is what Terraform figures out for you.
- The VPC ID and subnet ID output here are the inputs the ECS module will consume later.
