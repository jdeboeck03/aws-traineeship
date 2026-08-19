# Module Doc Template

Starting skeleton for `docs/content/<service>/index.md` when writing up a new AWS service module
(S3, IAM, DynamoDB, SQS+SNS, Lambda, CloudWatch, ...). Established while building out the EC2
module — see `CLAUDE.md` → Documentation conventions for the rules behind each piece and why they
exist. Copy the structure below and fill in the blanks; drop sections that genuinely don't apply to
the service (e.g. a fully serverless service may have no verify step), but keep the overall shape.

**Approach: copy-along, not exercise.** Terraform is the vehicle, not the subject. Show the code
directly with brief explanations of the non-obvious decisions. Trainees follow along and apply —
they are not expected to write the Terraform themselves.

**Manual exercise: EC2 only.** EC2 has an explicit Exercise 1 (console + CLI) because launching an
instance manually first makes AMIs, key pairs, and security groups concrete. From VPC onwards,
modules skip the manual exercise and go straight to Terraform. Add the following callout instead:

```shell
!!! info "No manual exercise for this module"
    From VPC onwards, modules go straight to Terraform. <Service> resources are infrastructure
    wiring — creating them by hand doesn't build intuition beyond what the concepts section covers,
    and manual cleanup is error-prone.

    EC2 is the exception: launching an instance manually first makes AMIs, key pairs, and security
    groups concrete before Terraform abstracts them away.
```

---

```markdown
# <SERVICE> — <One-line description>

<One paragraph: what the service is, why it exists, in plain terms.>

## Concepts

**<Term>**
<Definition.>

<Repeat per core concept. Add `!!! note` callouts for anything that changes over time or is
commonly misunderstood — see the "AMI IDs change constantly" note in ec2/index.md for the pattern.>

---

!!! info "No manual exercise for this module"
    From VPC onwards, modules go straight to Terraform. <Service> resources are infrastructure
    wiring — creating them by hand doesn't build intuition beyond what the concepts section covers,
    and manual cleanup is error-prone.

    EC2 is the exception: launching an instance manually first makes AMIs, key pairs, and security
    groups concrete before Terraform abstracts them away.

## Provisioning with Terraform

<One or two sentences on what this module creates and why.>

### `terraform/<service>/`

<File tree, then each file shown directly. After main.tf, add a short paragraph on anything
non-obvious — why a resource exists, why ordering matters, a gotcha to watch for. Don't explain
what the code does; explain why it's written that way.>

### Wire it into the full stack

<Show the module call to add to terraform/full-stack/main.tf, and any new variables/outputs
needed in the full-stack. Add `!!! failure` or `!!! warning` blocks for any realistic error.>

### Set your variables

<If new variables are needed in terraform.tfvars, show the additions.>

### Apply

<`init` / `plan` / `apply`. One sentence on what to check in the output.>

### Verify

<If there's a concrete way to verify the resource works (SSH, curl, console check), include it.
This is where the concept clicks — don't skip it if a good verify step exists.>

### Clean up

<`terraform destroy`. Call out any resources that need manual attention first (non-empty buckets,
etc.) with `!!! warning` blocks.>

---

## Key takeaways

<3-6 bullets. What should stick after this module.>
```

## Checklist before publishing a new module

- [ ] Every AWS-specific value asserted in the doc (pricing, free-tier eligibility, current AMI/
      resource metadata, exact error text) verified live against the real account, not recalled
      from memory — these change and are easy to get subtly wrong.
- [ ] Every documented command copy-pastes cleanly in both bash and PowerShell.
- [ ] Every resource gets `Project`/`Owner`/`Contact` tags via `default_tags` on the root provider.
- [ ] Cleanup steps cover every resource created, not just the headline one.
- [ ] No hardcoded values that go stale (AMI IDs, latest-version identifiers) — looked up
      dynamically instead.
- [ ] `mkdocs build --strict` passes, and any new admonition/tab/collapsible syntax actually
      renders (check the built HTML — don't assume a `pymdownx.*` extension is enabled).
- [ ] `terraform validate` (and ideally a live `terraform plan`) passes for any new/changed module.
