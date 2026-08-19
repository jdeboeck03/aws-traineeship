# EC2 — Virtual Machines

Amazon Elastic Compute Cloud (EC2) lets you rent virtual servers in the cloud. You choose the
operating system, CPU, memory, and storage — AWS handles the physical hardware underneath.

## Concepts

**AMI (Amazon Machine Image)**
A snapshot of an operating system and pre-installed software. Every EC2 instance is launched from
an AMI. AWS publishes official Amazon Linux, Ubuntu, and Windows images; you can also create your
own.

!!! note "AMI IDs change constantly"
    AWS ships a new Amazon Linux 2023 build every few weeks, each with a new AMI ID — the exact
    build number (e.g. `2023.12.20260803.3`) isn't important, only the family ("Amazon Linux
    2023"). Never hardcode an AMI ID for long-term use; look it up at launch time instead (the
    console does this for you, the CLI/Terraform examples below show how).

**Instance type**
Determines the vCPU count, memory, and network bandwidth of the instance.
`t3.micro` is the smallest general-purpose type and sits within the free tier.

**Key pair**
SSH public/private key pair used to authenticate to a Linux instance.
AWS stores the public key; you keep the private key (`.pem` file). Without it you cannot SSH in.

**Security group**
A stateful firewall attached to an instance. Rules are _allow-only_ — there is no explicit deny.
By default all inbound traffic is blocked and all outbound traffic is allowed. Security groups are
free — there's no cost to creating your own per instance, and doing so keeps your resources
isolated from everyone else's in this shared account.

**Public IP**
EC2 instances can be assigned a public IP on launch. By default this IP changes every time the
instance stops and starts. An **Elastic IP** (static public IP) can be assigned if you need a
stable address.

---

## Exercise 1 — Launch an instance manually

1. Open the [EC2 console](https://eu-west-1.console.aws.amazon.com/ec2/home?region=eu-west-1#Instances:)
   and click **Launch instance**.
2. Set a **Name** — use something unique, e.g. `ec2-<your-name>`.
3. Under **Application and OS Images** select **Amazon Linux 2023 AMI**.
4. Under **Instance type** choose `t3.micro`.
5. Under **Key pair** click **Create new key pair**:
    - Name: `<your-name>-key`
    - Type: RSA
    - Format: `.pem`
    - Download the file and keep it somewhere safe.
6. Under **Network settings** leave the defaults (auto-assign public IP enabled) and add a security
   group rule:
    - Type: SSH, Source: Anywhere (0.0.0.0/0)
7. Expand **Advanced details** and add the three required tags from [Tagging](../tagging/index.md)
   (`Project`, `Owner`, `Contact`), plus a `Name` tag matching the instance name you picked.
8. Click **Launch instance**.

!!! warning "The security group doesn't inherit these tags"
    Tags you set during launch only apply to the instance — the security group the wizard creates
    for you (named `launch-wizard-N`) comes out **untagged**. After launching, go to
    **EC2 → Security Groups**, select the one attached to your instance, open its **Tags** tab, and
    add the same `Project` / `Owner` / `Contact` tags manually.

### Connect via SSH

```shell
# Restrict permissions on the key file (required by SSH)
chmod 400 <your-name>-key.pem

# Connect — find the public IP in the EC2 console under Instance > Public IPv4 address
ssh -i <your-name>-key.pem ec2-user@<public-ip>
```

!!! tip "Windows users"
    Use **Git Bash**, **WSL**, or the native OpenSSH client in PowerShell.
    If you use PowerShell, replace `chmod 400` with:
    ```powershell
    icacls <your-name>-key.pem /inheritance:r /grant:r "$($env:USERNAME):R"
    ```

### Connect via CLI

You can also launch an instance entirely from the CLI. Unlike the console wizard, nothing is
created for you automatically — you create the security group, open port 22 on it, look up the
AMI, and launch the instance yourself, in that order. This is exactly what the Terraform module
further down this page does under the hood.

!!! danger "Don't skip the security group"
    `aws ec2 run-instances` without `--security-group-ids` attaches the instance to the VPC's
    **default** security group, which allows no inbound traffic at all — including SSH. You'd get
    an instance you can't connect to. Create and attach your own group as shown below.

=== "Linux / macOS"

    ```shell
    # Security group, scoped to your own instance, in the default VPC
    VPC_ID=$(aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" \
      --region eu-west-1 --query 'Vpcs[0].VpcId' --output text)

    SG_ID=$(aws ec2 create-security-group \
      --group-name <your-name>-sg --description "Allow SSH inbound" \
      --vpc-id "$VPC_ID" --region eu-west-1 --query 'GroupId' --output text)

    aws ec2 authorize-security-group-ingress \
      --group-id "$SG_ID" --protocol tcp --port 22 --cidr 0.0.0.0/0 \
      --region eu-west-1

    # Current Amazon Linux 2023 AMI
    AMI_ID=$(aws ssm get-parameter \
      --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
      --region eu-west-1 --query 'Parameter.Value' --output text)

    # Launch, referencing the security group above
    aws ec2 run-instances \
      --image-id "$AMI_ID" \
      --instance-type t3.micro \
      --key-name <your-name>-key \
      --security-group-ids "$SG_ID" \
      --region eu-west-1
    ```

=== "Windows (PowerShell)"

    ```powershell
    $VpcId = aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" `
      --region eu-west-1 --query "Vpcs[0].VpcId" --output text

    $SgId = aws ec2 create-security-group `
      --group-name <your-name>-sg --description "Allow SSH inbound" `
      --vpc-id $VpcId --region eu-west-1 --query "GroupId" --output text

    aws ec2 authorize-security-group-ingress `
      --group-id $SgId --protocol tcp --port 22 --cidr 0.0.0.0/0 `
      --region eu-west-1

    $AmiId = aws ssm get-parameter `
      --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 `
      --region eu-west-1 --query "Parameter.Value" --output text

    aws ec2 run-instances `
      --image-id $AmiId `
      --instance-type t3.micro `
      --key-name <your-name>-key `
      --security-group-ids $SgId `
      --region eu-west-1
    ```

!!! note "Don't forget the tags"
    Neither the instance nor the security group you just created are tagged yet. Add the required
    tags afterwards from the console, or pass `--tag-specifications` on `create-security-group` and
    `run-instances` to tag them at creation time — see [Tagging](../tagging/index.md).

### Clean up

Terminate the instance from the EC2 console (select it → **Instance state** → **Terminate
instance**) or via `aws ec2 terminate-instances --instance-ids <id>`.

!!! warning "The security group isn't deleted automatically"
    Unlike Terraform's `destroy` below, terminating an instance launched manually does **not**
    remove its security group — neither the console wizard's `launch-wizard-N` group nor the
    `<your-name>-sg` group created via the CLI above. Once the instance has finished terminating,
    delete it separately:
    ```shell
    aws ec2 delete-security-group --group-id <sg-id> --region eu-west-1
    ```
    or from **EC2 → Security Groups** in the console.

!!! warning "Neither is the key pair"
    Delete the key pair you created too, once you're done with this exercise:
    ```shell
    aws ec2 delete-key-pair --key-name <your-name>-key --region eu-west-1
    ```
    or from **EC2 → Key Pairs** in the console. If you skip this and move on to the Terraform
    section below with the same `<your-name>`, `terraform apply` will fail — it tries to create a
    key pair with that same name.

---

## Provisioning with Terraform

See [Terraform Fundamentals](../terraform-fundamentals/index.md) if you haven't installed
Terraform yet or need a refresher on the core concepts and workflow used below.

This reproduces Exercise 1 as code — an EC2 instance you can SSH into, with its own security
group, tagged per [Tagging](../tagging/index.md), running the current Amazon Linux 2023 AMI
without hardcoding an AMI ID. It's built as two pieces:

- `terraform/ec2/` is a reusable **child module** — resources and variables only, no provider
  configuration. It's designed to be composed: `subnet_id`, `security_group_ids`, and
  `iam_instance_profile` default to values that make it work standalone today, but later modules
  (Networking, IAM) will override them without you touching this file again.
- `terraform/full-stack/` is the **root module** — this is where the provider gets configured and
  where you actually run `terraform apply`. From here on, every module in this course gets wired
  into this same root and destroyed together in one `terraform destroy`. The mechanics of why
  child modules don't configure a provider are covered in
  [Terraform Modules](../terraform-modules/index.md), taught right after Networking.

### `terraform/ec2/`

```
terraform/ec2/
├── main.tf
├── variables.tf
└── outputs.tf
```

```hcl title="main.tf"
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

# Only create a security group when none are passed in — allows standalone use before a VPC exists.
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
  # SSM parameter values are marked sensitive by default — nonsensitive() unmarks it so the AMI ID
  # is still visible in plan/apply output.
  ami                         = nonsensitive(data.aws_ssm_parameter.al2023_ami.value)
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.this.key_name
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = length(var.security_group_ids) > 0 ? var.security_group_ids : [aws_security_group.this[0].id]
  associate_public_ip_address = true
  iam_instance_profile        = var.iam_instance_profile

  tags = {
    Name = var.name
  }
}
```

Notice there's no `provider` block here — child modules never configure a provider, that's the
root module's job. There's also no `terraform { required_providers { ... } }` block; that's
declared once in the root and inherited by every child.

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

variable "iam_instance_profile" {
  description = "Name of the IAM instance profile to attach. If null, the instance runs without a profile."
  type        = string
  default     = null
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

### Create the full-stack root

Since `terraform/ec2/` has no provider configuration, it can't be applied on its own — you need a
root module to call it from. Create `terraform/full-stack/`: this is the single place you'll run
`terraform apply`/`terraform destroy` for the rest of the course, growing by one `module` block
each time a new service is introduced.

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

module "ec2" {
  source  = "../ec2"
  name    = var.name
  owner   = var.owner
  contact = var.contact
  project = var.project
  region  = var.region
}
```

The provider's `default_tags` block means every resource any child module creates — the instance,
its security group, its key pair — is automatically tagged with `Project`, `Owner`, and `Contact`.
Nothing ends up untagged, and `terraform destroy` removes it all together.

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
output "public_ip" {
  description = "Public IP address of the EC2 instance."
  value       = module.ec2.public_ip
}

output "instance_id" {
  description = "EC2 instance ID."
  value       = module.ec2.instance_id
}

output "ssh_command" {
  description = "Ready-to-run SSH command."
  value       = module.ec2.ssh_command
}
```

### Set your variables

`name`, `owner`, `contact`, and `project` are all required, with no defaults. Rather than repeating
four `-var=...` flags on every command, create a `terraform.tfvars` file in `terraform/full-stack/`
— Terraform loads it automatically, and it's already git-ignored so nothing personal gets committed
(see [Terraform Fundamentals](../terraform-fundamentals/index.md#providing-variable-values)):

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

Terraform prints the instance's **public IP** when it finishes. The private key was written to
`terraform/full-stack/<your-name>-key.pem` — that's the directory you ran `apply` from.

```shell
# SSH in using the generated key
chmod 400 <your-name>-key.pem
ssh -i <your-name>-key.pem ec2-user@<printed-public-ip>
```

### Clean up

```shell
terraform destroy
```

As more modules get added to `terraform/full-stack/` throughout the course, this same command
tears down everything created so far, in the correct dependency order.

---

## Key takeaways

- EC2 gives you a full virtual machine — full control, but you manage the OS.
- Security groups are the primary network-level access control mechanism, and they're free to
  create one per instance — do so rather than sharing one across trainees.
- Key pairs are the only way into a Linux instance; keep your `.pem` file secure.
- Tags don't propagate automatically between related resources — a security group created
  alongside a tagged instance still needs its own tags.
- The `terraform/ec2/` module has no provider block and optional subnet/security-group/profile
  inputs — it's designed to be composed. `terraform/full-stack/` is the root module where the
  provider lives and where every later module gets wired in and destroyed together.
- In later modules we will move to higher-level abstractions (ECS Fargate) where AWS manages the
  underlying VM for you.
