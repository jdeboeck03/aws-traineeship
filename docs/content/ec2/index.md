# EC2 — Virtual Machines

Amazon Elastic Compute Cloud (EC2) lets you rent virtual servers in the cloud. You choose the
operating system, CPU, memory, and storage — AWS handles the physical hardware underneath.

## Concepts

**AMI (Amazon Machine Image)**
A snapshot of an operating system and pre-installed software. Every EC2 instance is launched from
an AMI. AWS publishes official Amazon Linux, Ubuntu, and Windows images; you can also create your
own.

**Instance type**
Determines the vCPU count, memory, and network bandwidth of the instance.
`t3.micro` is the smallest general-purpose type and sits within the free tier.

**Key pair**
SSH public/private key pair used to authenticate to a Linux instance.
AWS stores the public key; you keep the private key (`.pem` file). Without it you cannot SSH in.

**Security group**
A stateful firewall attached to an instance. Rules are _allow-only_ — there is no explicit deny.
By default all inbound traffic is blocked and all outbound traffic is allowed.

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
7. Click **Launch instance**.

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

You can also launch an instance entirely from the CLI:

```shell
aws ec2 run-instances \
  --image-id ami-089950bc622d39ed8 \
  --instance-type t3.micro \
  --key-name <your-name>-key \
  --region eu-west-1
```

---

## Exercise 2 — Provision with Terraform

### Prerequisites

Install Terraform by following the [official instructions](https://developer.hashicorp.com/terraform/install).
Verify:

```shell
terraform -version
```

### Project layout

```
terraform/ec2/
├── main.tf          # provider and resources
├── variables.tf     # input variables
└── outputs.tf       # useful values printed after apply
```

The full source is in [`terraform/ec2/`](https://github.com/your-repo/terraform/ec2) in this repo.

### Initialise and apply

```shell
cd terraform/ec2

# Download the AWS provider
terraform init

# Preview what will be created
terraform plan -var="name=<your-name>"

# Create the resources
terraform apply -var="name=<your-name>"
```

Terraform will print the instance's **public IP** when it finishes.

```shell
# SSH in using the generated key
chmod 400 <your-name>-key.pem
ssh -i <your-name>-key.pem ec2-user@<printed-public-ip>
```

### Clean up

Always destroy resources when you are done to avoid unnecessary costs:

```shell
terraform destroy -var="name=<your-name>"
```

---

## Key takeaways

- EC2 gives you a full virtual machine — full control, but you manage the OS.
- Security groups are the primary network-level access control mechanism.
- Key pairs are the only way into a Linux instance; keep your `.pem` file secure.
- Terraform lets you define infrastructure as code so it is repeatable and reviewable.
- In later modules we will move to higher-level abstractions (ECS Fargate) where AWS manages the
  underlying VM for you.
