# Module Doc Template

Starting skeleton for `docs/content/<service>/index.md` when writing up a new AWS service module
(VPC, S3, IAM, DynamoDB, SQS+SNS, Lambda, CloudWatch, ...). Established while building out the EC2
module — see `CLAUDE.md` → Documentation conventions for the rules behind each piece and why they
exist. Copy the structure below and fill in the blanks; drop sections that genuinely don't apply to
the service (e.g. a fully serverless service may have no "Connect via CLI"-equivalent), but don't
drop the tagging, cleanup, or hints/solution structure without a specific reason.

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

## Exercise 1 — <Verb> manually

<Numbered console steps. Include an explicit tagging step (Project/Owner/Contact + Name) — don't
assume it happens automatically. If the console flow creates any secondary/auxiliary resource (a
security group, a role, a bucket policy, ...), check whether it inherits tags from the "main"
resource — it usually doesn't — and give it its own step plus a `!!! warning` callout.>

### <Do it via CLI>  <!-- e.g. "Connect via CLI" -->

<Full working CLI command(s). Wrap in `=== "Linux / macOS"` / `=== "Windows (PowerShell)"` tabs
(`pymdownx.tabbed`) if there's any shell-specific syntax — line continuation, variable assignment,
quoting. Look up anything that drifts over time (AMI IDs, latest image tags, current-generation
instance/resource types) dynamically; never hardcode an identifier that will go stale.>

### Clean up

<Tear-down steps for EVERYTHING created in this exercise, including secondary resources not deleted
automatically alongside the "main" one (e.g. a security group surviving instance termination). Give
the actual CLI command, not just "delete it in the console.">

---

## Exercise 2 — Provision with Terraform

See [Terraform Fundamentals](../terraform-fundamentals/index.md) if needed.

### Your task

<State the goal and a bullet list of hard requirements — what the module must produce, not how to
write it.>

??? question "Hints"
    <Bullet hints pointing at the right resources/data sources/providers/variables, without giving
    away exact resource blocks or attribute syntax.>

??? example "Show solution"
    <Full working `main.tf` / `variables.tf` / `outputs.tf`, pasted inline in full. No link to the
    GitHub repo — the code is already here, and a repo link lets trainees browse ahead into modules
    not taught yet.>

### Set your variables

<If the module has more than ~2 required variables, point at the `terraform.tfvars` pattern from
Terraform Fundamentals instead of a growing `-var=...` chain.>

### Initialise and apply

<`init` / `plan` / `apply`. Add `!!! failure` blocks for any error a trainee will realistically
hit — reproduce the exact error text against the real AWS account before writing it down, don't
guess it.>

### Clean up

<`terraform destroy`.>

---

## Key takeaways

<3-6 bullets. What should stick after this module.>
```

## Checklist before publishing a new module

- [ ] Every AWS-specific value asserted in the doc (pricing, free-tier eligibility, current AMI/
      resource metadata, exact error text) verified live against the real account, not recalled
      from memory — these change and are easy to get subtly wrong.
- [ ] Every documented command copy-pastes cleanly in both bash and PowerShell.
- [ ] Every resource gets `Project`/`Owner`/`Contact` tags, including secondary/auxiliary resources
      the console or CLI creates as a side effect.
- [ ] Cleanup steps cover every resource created, not just the headline one.
- [ ] No hardcoded values that go stale (AMI IDs, latest-version identifiers) — looked up
      dynamically instead.
- [ ] Terraform Exercise 2 is hints-first: task + requirements visible, hints and full solution
      collapsed, no link to the public repo.
- [ ] `mkdocs build --strict` passes, and any new admonition/tab/collapsible syntax actually
      renders (check the built HTML — don't assume a `pymdownx.*` extension is enabled).
- [ ] `terraform validate` (and ideally a live `terraform plan`) passes for any new/changed module.
