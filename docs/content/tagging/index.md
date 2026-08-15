# Tagging

This AWS account is shared by every trainee. Without a consistent way to tell resources apart,
it becomes hard to answer basic questions: whose EC2 instance is this, which project is it part
of, and who do I ask before deleting it? Tags solve this.

## Required tags

Every resource you create — through the console, the CLI, or Terraform — must carry these three
tags:

| Key       | Value                          | Example                       |
|-----------|--------------------------------|--------------------------------|
| `Project` | `SDT-Traineeship`               | `SDT-Traineeship`               |
| `Owner`   | `firstname.lastname`            | `jelle.deboeck`                |
| `Contact` | your email address              | `jelle.deboeck@axxes.com`      |

!!! note "Allowed characters"
    AWS tag keys and values only allow letters, numbers, spaces, and `+ - = . _ : / @`.
    `SDT-Traineeship` uses a hyphen, which is on that list, so it's a valid tag value.

## Tagging manually (console / CLI)

If you create a resource through the console, add the three tags under the **Tags** section of
the creation wizard before you click create. From the CLI, pass `--tag-specifications` (or the
equivalent flag for the service you're using) with all three key/value pairs.

This works, but it's easy to forget — especially once you're creating several resources per
module.

## Tagging automatically with Terraform

Since almost everything in this traineeship is provisioned with Terraform, the reliable fix is to
set tags **once, at the provider level**, instead of repeating a `tags = { ... }` block on every
resource. The AWS provider supports a `default_tags` block that applies to every resource it
manages:

```hcl
provider "aws" {
  region  = var.region
  profile = "traineeship"

  default_tags {
    tags = {
      Project = "SDT-Traineeship"
      Owner   = var.owner
      Contact = var.contact
    }
  }
}
```

With this in place, every `aws_*` resource created by that provider is tagged automatically — no
per-resource boilerplate, and no risk of forgetting a resource. If a resource also needs its own
tag (like a `Name` tag for readability), you can still add a `tags` block on that resource; it
merges with the default tags, and only overlapping keys get overridden.

```hcl
resource "aws_instance" "this" {
  # ...

  tags = {
    Name = var.name # merges with Project/Owner/Contact from default_tags
  }
}
```

`owner` and `contact` are plain input variables — pass your own values with
`-var="owner=..."` and `-var="contact=..."` (or set them in a `.tfvars` file, which is
git-ignored in this repo).

**Every module's `terraform/` directory in this repo follows this pattern.** When you write a new
root module, copy the `default_tags` block into its `provider "aws"` block rather than tagging
resources individually.

## Key takeaways

- Every resource needs `Project`, `Owner`, and `Contact` tags.
- Tagging manually works but doesn't scale — you will forget eventually.
- Terraform's `default_tags` on the provider block tags everything automatically and is the
  pattern used throughout this repo.
