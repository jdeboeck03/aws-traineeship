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
AMI, and launch the instance yourself, in that order. This is exactly what the Terraform module in
Exercise 2 does under the hood.

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

---

## Exercise 2 — Provision with Terraform

See [Terraform Fundamentals](../terraform-fundamentals/index.md) if you haven't installed
Terraform yet or need a refresher on the core concepts and workflow used below.

### Project layout

```
terraform/ec2/
├── main.tf          # provider and resources
├── variables.tf     # input variables
└── outputs.tf       # useful values printed after apply
```

The full source is in [`terraform/ec2/`](https://github.com/jdeboeck03/aws-traineeship/tree/main/terraform/ec2) in this repo.

The provider block sets `default_tags` so every resource this module creates is automatically
tagged with `Project`, `Owner`, and `Contact` — see [Tagging](../tagging/index.md). This is why
`owner` and `contact` are required variables below alongside `name`. This includes the security
group, which also gets a `Name` tag — unlike the console flow above, nothing here ends up
untagged, and `terraform destroy` removes the instance and its security group together.

The AMI is looked up automatically too, via the same SSM parameter used in the CLI example above —
`ami_id` only needs to be set if you want to pin a specific build.

### Initialise and apply

```shell
cd terraform/ec2

# Download the AWS provider
terraform init

# Preview what will be created
terraform plan -var="name=<your-name>" -var="owner=<your-name>.<your-lastname>" -var="contact=<you>@axxes.com"

# Create the resources
terraform apply -var="name=<your-name>" -var="owner=<your-name>.<your-lastname>" -var="contact=<you>@axxes.com"
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
terraform destroy -var="name=<your-name>" -var="owner=<your-name>.<your-lastname>" -var="contact=<you>@axxes.com"
```

---

## Key takeaways

- EC2 gives you a full virtual machine — full control, but you manage the OS.
- Security groups are the primary network-level access control mechanism, and they're free to
  create one per instance — do so rather than sharing one across trainees.
- Key pairs are the only way into a Linux instance; keep your `.pem` file secure.
- Tags don't propagate automatically between related resources — a security group created
  alongside a tagged instance still needs its own tags.
- Terraform lets you define infrastructure as code so it is repeatable and reviewable, and cleans
  up everything it created — including security groups — in one `destroy`.
- In later modules we will move to higher-level abstractions (ECS Fargate) where AWS manages the
  underlying VM for you.
