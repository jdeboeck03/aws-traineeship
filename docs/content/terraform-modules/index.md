# Terraform Modules

You've already done module composition — you just didn't stop to name it. In the EC2 module,
`terraform/ec2/` became the first child module, called from `terraform/full-stack/`. In Networking,
you added `terraform/vpc/` as a second child and wired its subnet ID into the `ec2` module's input.
This page names the mechanics behind what you already built, so you can extend the pattern
confidently as S3, IAM, and every later module get added the same way.

## Concepts

**Root module vs. child module**
Any directory with `.tf` files is a module. When you run `terraform apply` you are in the *root*
module — the entry point Terraform starts from. A *child* module is any module the root (or another
module) calls with a `module` block. The distinction is positional, not structural: the same `vpc/`
directory would be a standalone root if you configured a provider and `cd`'d into it — but in this
course, every service module is written to be a child from the start, which is why none of them
have a `provider` block.

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
registers the new source path — this is why every module doc's "Apply" step includes `terraform
init` with a comment reminding you it's only needed after adding a module.

**Referencing module outputs**
A child module's outputs are available in the root as `module.<name>.<output>`:

```hcl
module "ec2" {
  source    = "../ec2"
  subnet_id = module.vpc.public_subnet_id   # vpc output → ec2 input
}
```

This is how you wire services together without hardcoding IDs — exactly what you did when you
passed `module.vpc.public_subnet_id` into the `ec2` module's `subnet_id` in the Networking module.

**Provider inheritance**
Declare the provider (`aws`) once in the root module. Child modules inherit it automatically — you
never add a `provider` block inside `vpc/` or `ec2/`. This is a hard rule in this course, not just a
convention: a `provider` block inside a child would create a second, independent provider instance,
which could silently diverge from the root's region, profile, or `default_tags`.

**Resources that span modules belong in the root**
The SSH security group you created in the Networking module is a good example: it needs the VPC's
ID (an output only available *after* calling `module.vpc`) and feeds into the EC2 module as an
input. It doesn't belong inside `vpc/` (which shouldn't know about EC2) or `ec2/` (which shouldn't
know about VPC) — it belongs in the root, which is the only place that sees both.

**State and destroy order**
All resources created by the root and its children live in one state file. `terraform destroy`
removes them in the correct dependency order automatically — this is the practical payoff of the
incremental full-stack approach: one command tears down everything built across every module so
far, regardless of how many child modules are involved.

---

## Key takeaways

- A root module calls child modules with `module` blocks; child module outputs are referenced as
  `module.<name>.<output>`.
- Declare the provider once in the root — child modules inherit it automatically. A `provider`
  block inside a child module is a bug in this course's convention, not a harmless leftover.
- Run `terraform init` after adding a `module` block to register the new source path.
- All state lives in one file at the root level; `terraform destroy` handles teardown order across
  every child module, no matter how many have accumulated.
- Resources that span modules — needing one module's output as another's input — are defined in the
  root, not inside either child. This keeps each child module focused and independently reusable.
