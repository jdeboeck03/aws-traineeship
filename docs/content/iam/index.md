# IAM — Identity and Access Management

AWS Identity and Access Management (IAM) controls *who* can do *what* on *which* resources.
Every API call in AWS — whether from a developer in the console, a running EC2 instance, or an ECS
task — is authenticated by IAM and evaluated against a set of policies before being allowed or
denied. Understanding IAM is a prerequisite for every module that follows.

## Concepts

**Principal**
An entity that can make requests to AWS: an IAM user, an IAM role, an AWS service, or an external
identity. Every API call is made *on behalf of* a principal.

**Policy**
A JSON document that defines permissions: which **actions** (e.g. `s3:GetObject`) are allowed or
denied, on which **resources** (e.g. a specific S3 bucket ARN), and under which **conditions**.
Policies are attached to principals to grant them permissions.

**IAM Role**
An identity with a set of permissions that can be *assumed* by a principal. Unlike a user, a role
has no permanent password or access keys — when assumed, AWS issues short-lived temporary
credentials (valid for up to 12 hours). Roles are the recommended way to grant permissions to AWS
services, applications, and human operators.

**Trust policy**
Every role has two policy documents. The **trust policy** (also called the assume-role policy)
defines *who is allowed to assume the role* — e.g. "the EC2 service may assume this role." It uses
the `sts:AssumeRole` action and is set on the role itself.

**Permission policy**
The **permission policy** defines *what the role can do once assumed* — e.g. "read objects from
this S3 bucket." One or more permission policies are attached to the role.

**Instance profile**
EC2 instances don't assume roles directly — they use an **instance profile**, which is a thin
container for a single IAM role. When you attach an instance profile to an instance, the instance
metadata service (IMDS) automatically vends rotating temporary credentials for the role. Code
running on the instance picks these up transparently via the AWS SDK — no access keys needed.

!!! note "Task roles for ECS"
    ECS has the same concept under a different name: the **task role**. The only difference is the
    trust principal — instead of `ec2.amazonaws.com`, it's `ecs-tasks.amazonaws.com`. The rest of
    the model (trust policy → role → permission policy) is identical.

**Inline vs. managed policies**
- An **inline policy** is embedded directly in a role (or user/group) and lives and dies with it.
- A **managed policy** is a standalone resource with its own ARN. It can be attached to multiple
  roles, versioned independently, and audited separately.

Prefer managed policies: they're reusable, independently auditable, and visible in the IAM console
without opening the role. AWS also ships a library of pre-built **AWS managed policies** (e.g.
`AmazonS3ReadOnlyAccess`) you can attach directly — useful for broad permissions, though a
custom policy scoped to your specific bucket is always better.

**Least privilege**
Grant only the permissions the principal actually needs — nothing more. A role that only needs to
read one S3 bucket should not have `s3:*` on `*`. Scope both the actions and the resource ARN as
tightly as possible.

!!! note "IAM is global"
    IAM resources (roles, policies, instance profiles) are not region-specific — they exist at the
    account level. You create them once and they're available in every region.

---

!!! info "No manual exercise for this module"
    From VPC onwards, modules go straight to Terraform. IAM resources (roles, policies, instance
    profiles) are infrastructure wiring — creating them by hand doesn't build intuition beyond what
    the concepts section covers, and the console makes it easy to mis-scope policies or forget
    attachments. Terraform makes the trust policy and permission policy explicit and reviewable.

    EC2 is the exception: launching an instance manually first makes AMIs, key pairs, and security
    groups concrete before Terraform abstracts them away.

## Exercise — Provision with Terraform

See [Terraform Fundamentals](../terraform-fundamentals/index.md) if you haven't used Terraform yet
or need a refresher.

### Your task

Build a Terraform module in `terraform/iam/` that creates an IAM role for your EC2 instance to
assume, with a scoped permission policy allowing it to read from your S3 bucket.

It should:

- Create an IAM role that the EC2 service can assume (trust policy: `ec2.amazonaws.com`)
- Create a **custom managed policy** that grants `s3:GetObject` and `s3:ListBucket` on your S3
  bucket only — not on `*`
- Attach the policy to the role
- Create an instance profile wrapping the role
- Take `name` and `bucket_name` as required variables
- Output the instance profile name so the full-stack can pass it to the EC2 module

??? question "Hints"
    - The four resources you need: `aws_iam_role`, `aws_iam_policy`, `aws_iam_role_policy_attachment`,
      `aws_iam_instance_profile`. Look them up in the
      [Terraform Registry](https://registry.terraform.io/providers/hashicorp/aws/latest/docs).
    - The trust policy lives in `aws_iam_role`'s `assume_role_policy` argument. Use `jsonencode()`
      to write it as HCL rather than an escaped string. The `Action` is `"sts:AssumeRole"` and the
      `Principal` is `{ Service = "ec2.amazonaws.com" }`.
    - The permission policy is a separate `aws_iam_policy` resource. Scope the `Resource` to both
      `arn:aws:s3:::${var.bucket_name}` (for `ListBucket`) and `arn:aws:s3:::${var.bucket_name}/*`
      (for `GetObject`) — `ListBucket` is a bucket-level action, `GetObject` is an object-level one,
      and they need separate ARN patterns.
    - `aws_iam_role_policy_attachment` connects the two: `role = aws_iam_role.ec2.name` and
      `policy_arn = aws_iam_policy.s3_read.arn`.
    - `aws_iam_instance_profile` just wraps the role: `role = aws_iam_role.ec2.name`.

??? example "Show solution"
    ```
    terraform/iam/
    ├── main.tf
    ├── variables.tf
    └── outputs.tf
    ```

    ```hcl title="main.tf"
    resource "aws_iam_role" "ec2" {
      name = "${var.name}-ec2-role"

      assume_role_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
          {
            Effect = "Allow"
            Principal = {
              Service = "ec2.amazonaws.com"
            }
            Action = "sts:AssumeRole"
          }
        ]
      })

      tags = {
        Name = "${var.name}-ec2-role"
      }
    }

    resource "aws_iam_policy" "s3_read" {
      name        = "${var.name}-s3-read"
      description = "Read-only access to the ${var.bucket_name} S3 bucket."

      policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
          {
            Effect = "Allow"
            Action = [
              "s3:GetObject",
              "s3:ListBucket",
            ]
            Resource = [
              "arn:aws:s3:::${var.bucket_name}",
              "arn:aws:s3:::${var.bucket_name}/*",
            ]
          }
        ]
      })

      tags = {
        Name = "${var.name}-s3-read"
      }
    }

    resource "aws_iam_role_policy_attachment" "s3_read" {
      role       = aws_iam_role.ec2.name
      policy_arn = aws_iam_policy.s3_read.arn
    }

    resource "aws_iam_instance_profile" "ec2" {
      name = "${var.name}-ec2-profile"
      role = aws_iam_role.ec2.name

      tags = {
        Name = "${var.name}-ec2-profile"
      }
    }
    ```

    ```hcl title="variables.tf"
    variable "name" {
      description = "Unique name used as a prefix for all resource Name tags."
      type        = string
    }

    variable "bucket_name" {
      description = "Name of the S3 bucket the EC2 role is allowed to read."
      type        = string
    }
    ```

    ```hcl title="outputs.tf"
    output "instance_profile_name" {
      description = "Name of the IAM instance profile to attach to the EC2 instance."
      value       = aws_iam_instance_profile.ec2.name
    }
    ```

### Wire it into the full stack

Add the IAM module to `terraform/full-stack/main.tf` and pass its output to the EC2 module:

```hcl
module "iam" {
  source      = "../iam"
  name        = var.name
  bucket_name = var.bucket_name
}
```

Then update the EC2 module call to pass the instance profile:

```hcl
module "ec2" {
  # ... existing arguments ...
  iam_instance_profile = module.iam.instance_profile_name
}
```

The EC2 module accepts an optional `iam_instance_profile` variable. Terraform automatically applies
`module.iam` before `module.ec2` because it sees the reference — no explicit `depends_on` needed.

### Apply

```shell
cd terraform/full-stack

terraform init   # only needed after adding a new module
terraform plan
terraform apply
```

### Verify

SSH into the EC2 instance (use the `ssh_command` output) and confirm it can access your S3 bucket
without any credentials configured:

```shell
# List objects in your bucket — works because the instance profile provides credentials via IMDS
aws s3 ls s3://<your-bucket-name>

# Download the index.html you uploaded earlier
aws s3 cp s3://<your-bucket-name>/index.html .
cat index.html
```

If both commands succeed, the instance profile is working correctly. Try a bucket you don't own to
confirm the policy is scoped — it should return `Access Denied`.

### Clean up

IAM resources are destroyed together with the rest of the stack at the end of the day:

```shell
terraform destroy
```

!!! warning "Policy name conflicts on re-apply"
    IAM policy names are unique per account. If you destroy and re-apply, Terraform may hit a
    conflict if the old policy wasn't fully deleted before the new one is created. Wait a few
    seconds and retry — IAM deletions are eventually consistent.

---

## Key takeaways

- Every AWS API call is authenticated by IAM; a principal (user, role, service) must be allowed
  to perform the action on the target resource.
- A role has two separate policy documents: the **trust policy** (who can assume it) and the
  **permission policy** (what it can do). Both must be correct for access to work.
- EC2 instances assume roles via an **instance profile**. The AWS SDK picks up the resulting
  temporary credentials from the instance metadata service automatically — no access keys on disk.
- ECS tasks use the same model with a **task role**; the only difference is the trust principal
  (`ecs-tasks.amazonaws.com` instead of `ec2.amazonaws.com`).
- Scope permission policies tightly: specific actions, specific resource ARNs. `s3:*` on `*` is
  never the right answer for a production workload.
- `ListBucket` and `GetObject` need different ARN patterns (`arn:aws:s3:::bucket` vs
  `arn:aws:s3:::bucket/*`) — a common mistake that produces confusing `Access Denied` errors.
