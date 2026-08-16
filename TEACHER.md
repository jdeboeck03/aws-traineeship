# Teacher Reference

Quick navigation to the standalone module solutions, for reference when presenting a module before
trainees have completed later composition exercises.

## Standalone solutions

| Module | Standalone Terraform | Notes |
|--------|---------------------|-------|
| EC2 | `terraform/ec2/` | Standalone — creates its own default SG (port 22), key pair, and instance in the default VPC. Run from `terraform/ec2/` with a `terraform.tfvars` there. |
| VPC | `terraform/vpc/` | Standalone — VPC, public subnet, IGW, route table. No security group. Run from `terraform/vpc/`. |
| Terraform Modules (full-stack) | `terraform/full-stack/` | Composition — calls `vpc` and `ec2` modules, adds its own SSH security group, wires them together. Run from `terraform/full-stack/`. |

## Notes on running standalone vs. composed

- The EC2 module's `security_group_ids` variable defaults to `[]`. When empty, the module creates
  its own security group (port 22). When the full-stack module passes a list, the EC2 module's own
  SG is skipped — so the same module code works both standalone and composed.
- The `vpc` module has no SSH security group — that resource lives in the full-stack root module.
  This keeps the VPC module general-purpose and reusable.
- Key pairs created by `terraform/ec2/` are not destroyed by `terraform destroy` in `full-stack/` —
  they live in the EC2 module's own state. Run `terraform destroy` from `terraform/ec2/` separately
  if needed.

## Module interdependencies

```
full-stack/main.tf
├── module "vpc"  →  terraform/vpc/
├── aws_security_group.ssh  (needs module.vpc.vpc_id)
└── module "ec2"  →  terraform/ec2/
      ├── subnet_id          = module.vpc.public_subnet_id
      └── security_group_ids = [aws_security_group.ssh.id]
```
