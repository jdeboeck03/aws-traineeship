# S3 — Object Storage

Amazon Simple Storage Service (S3) is AWS's object storage: a place to store any file — images,
logs, deployment artifacts, static websites, backups — at virtually unlimited scale. Objects live in
**buckets** and are addressed by a key (a string that looks like a file path). S3 has no file
system; the hierarchy you see in the console is just a naming convention on flat key names.

## Concepts

**Bucket**
The top-level container for objects. Bucket names must be globally unique across all AWS accounts
and regions. Once you pick a name, no other AWS customer can use it. Buckets are created in a
specific region; objects don't automatically replicate to other regions.

**Object**
A file stored in a bucket, identified by its **key** (e.g. `uploads/2026/photo.jpg`). An object
also carries metadata (content type, custom headers) and the object's data body. The maximum object
size is 5 TB; anything over 5 GB requires multipart upload (the AWS SDK does this transparently).

**Key**
The full "path" of an object within a bucket. S3 has no real directories — the `/` in a key is
just a convention that the console renders as folder nesting.

**Bucket policy**
A JSON document attached to a bucket that controls access at the bucket level. Used to make objects
publicly readable, restrict access to specific IAM principals, or enforce HTTPS-only access.
Distinct from IAM policies (which attach to users/roles): a bucket policy lives on the resource and
is evaluated in addition to the caller's IAM permissions.

**ACL (Access Control List)**
An older, per-object or per-bucket access mechanism. AWS now recommends disabling ACLs and
controlling access with bucket policies instead — new buckets have ACLs disabled by default since
April 2023.

!!! note "Block Public Access"
    By default, AWS enables **Block Public Access** on every new bucket — four settings that
    override any bucket policy or ACL that would make objects public. You must explicitly disable
    the relevant settings to host a public static website or share objects publicly. This is a
    safety net against accidental data exposure.

**Presigned URL**
A time-limited URL that grants temporary access to a private object without exposing AWS
credentials. The server generates it using its credentials and gives it to the client; the client
uses the URL directly. Common pattern: generate a presigned URL server-side, return it to the
browser, browser uploads or downloads directly to S3.

**Static website hosting**
S3 can serve a bucket's contents as a static website — HTML, CSS, JS, images — directly over HTTP.
No server required. Useful for hosting documentation sites or single-page apps cheaply. HTTPS
requires CloudFront in front; plain HTTP is served natively.

**Storage class**
S3 offers several tiers trading cost for retrieval speed: **Standard** (default, instant access),
**Standard-IA** (infrequent access, lower storage cost, per-retrieval fee), **Glacier** (archival,
minutes-to-hours retrieval), and others. You can set the class per object or use lifecycle rules to
transition objects automatically.

!!! note "Free tier"
    S3 is covered by the AWS free tier: 5 GB of Standard storage, 20,000 GET requests, and 2,000
    PUT requests per month for the first 12 months. Verify current limits at
    [aws.amazon.com/free](https://aws.amazon.com/free) — these change over time.

---

!!! info "No manual exercise for this module"
    From VPC onwards, modules go straight to Terraform. S3 buckets are straightforward to create in
    the console, but Terraform is more interesting here — bucket policies, versioning, and public
    access settings are easy to get wrong in the console and hard to audit. Terraform makes the
    intended state explicit and reviewable.

    EC2 is the exception: launching an instance manually first makes AMIs, key pairs, and security
    groups concrete before Terraform abstracts them away.

## Provisioning with Terraform

The S3 module creates a publicly readable static website bucket and uploads a minimal `index.html`.

### `terraform/s3/`

```
terraform/s3/
├── main.tf
├── variables.tf
├── outputs.tf
└── index.html
```

```hcl title="main.tf"
resource "aws_s3_bucket" "this" {
  bucket = var.bucket_name

  tags = {
    Name = var.bucket_name
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_website_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  index_document {
    suffix = "index.html"
  }
}

resource "aws_s3_bucket_policy" "public_read" {
  bucket = aws_s3_bucket.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.this.arn}/*"
      }
    ]
  })

  # Block Public Access must be disabled before the policy can be applied.
  depends_on = [aws_s3_bucket_public_access_block.this]
}

resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.this.id
  key          = "index.html"
  source       = "${path.module}/index.html"
  content_type = "text/html"
}
```

S3 configuration is split across multiple resources — `aws_s3_bucket` only creates the bucket;
website hosting, public access settings, and policies are each their own resource. The `depends_on`
on the policy is required: AWS rejects a public bucket policy while Block Public Access is still
enabled, and Terraform needs an explicit hint to sequence them correctly.

```hcl title="variables.tf"
variable "bucket_name" {
  description = "Globally unique S3 bucket name."
  type        = string
}
```

```hcl title="outputs.tf"
output "bucket_name" {
  description = "Name of the S3 bucket."
  value       = aws_s3_bucket.this.id
}

output "website_endpoint" {
  description = "HTTP endpoint for the static website."
  value       = "http://${aws_s3_bucket_website_configuration.this.website_endpoint}"
}
```

```html title="index.html"
<!DOCTYPE html>
<html lang="en">
<head><meta charset="UTF-8"><title>Hello from S3</title></head>
<body>
  <h1>Hello from S3!</h1>
  <p>This page is served directly from an S3 bucket.</p>
</body>
</html>
```

### Wire it into the full stack

Add the S3 module to `terraform/full-stack/main.tf`:

```hcl
module "s3" {
  source      = "../s3"
  bucket_name = var.bucket_name
}
```

Add `bucket_name` to `terraform/full-stack/variables.tf`:

```hcl
variable "bucket_name" {
  description = "Globally unique S3 bucket name, e.g. <your-name>-traineeship-site."
  type        = string
}
```

### Set your variables

Add `bucket_name` to `terraform/full-stack/terraform.tfvars`:

```hcl
bucket_name = "<your-name>-traineeship-site"
```

!!! warning "Bucket names are globally unique"
    If `<your-name>-traineeship-site` is already taken by another AWS account, `terraform apply`
    will fail with `BucketAlreadyExists`. Add a short suffix (e.g. your initials or a number) to
    make the name unique.

### Apply

```shell
cd terraform/full-stack

terraform init   # only needed after adding a new module
terraform plan
terraform apply
```

After apply, Terraform prints the `website_endpoint` output. Open it in a browser — you should see
your `index.html` served over HTTP.

### Clean up

The S3 resources are destroyed together with the rest of the stack at the end of the day:

```shell
terraform destroy
```

!!! warning "Non-empty buckets cannot be destroyed"
    `terraform destroy` will fail if the bucket contains objects that Terraform didn't create —
    any files you uploaded manually (e.g. via the console) are not tracked and won't be deleted
    automatically. Either empty the bucket first in the console (S3 → bucket → **Empty**), or add
    `force_destroy = true` to the `aws_s3_bucket` resource before running `destroy`.

---

## Key takeaways

- S3 stores objects (files) in buckets; keys look like paths but there is no real directory
  structure — it's a flat namespace with `/` in key names as a naming convention.
- Bucket names are globally unique across all AWS accounts. A name conflict from another account
  returns `BucketAlreadyExists`.
- Block Public Access is on by default — you must explicitly turn it off before a bucket policy
  can make objects public. This is a deliberate safety net.
- Bucket policies live on the resource (not on an IAM user/role) and control who can access
  objects. The `Resource` ARN must end in `/*` to grant access to objects, not just the bucket.
- `aws_s3_bucket_public_access_block` and `aws_s3_bucket_policy` are separate resources from
  `aws_s3_bucket` — use `depends_on` when ordering matters.
- A non-empty bucket cannot be destroyed with `terraform destroy` unless `force_destroy = true`
  is set — manual uploads survive `destroy` and must be emptied first.
