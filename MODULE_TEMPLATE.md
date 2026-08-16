# Module Doc Template

Starting skeleton for `docs/content/<service>/index.md` when writing up a new AWS service module
(S3, IAM, DynamoDB, SQS+SNS, Lambda, CloudWatch, ...). Established while building out the EC2
module — see `CLAUDE.md` → Documentation conventions for the rules behind each piece and why they
exist. Copy the structure below and fill in the blanks; drop sections that genuinely don't apply to
the service (e.g. a fully serverless service may have no "Connect via CLI"-equivalent), but don't
drop the hints/solution structure without a specific reason.

**Manual exercise: EC2 only.** EC2 has an explicit Exercise 1 (console + CLI) because launching an
instance manually first makes AMIs, key pairs, and security groups concrete. From VPC onwards,
modules skip the manual exercise and go straight to Terraform — infrastructure wiring resources
(subnets, route tables, IAM roles, ...) don't build intuition from manual creation, and the cleanup
steps multiply the risk of leftover resources. Add the following callout instead of an Exercise 1:

```shell
!!! info "No manual exercise for this module"
    From VPC onwards, modules go straight to Terraform. <Service> resources are infrastructure
    wiring — creating them by hand doesn't build intuition beyond what the concepts section covers,
    and manual cleanup is error-prone. Terraform also produces outputs that later modules consume
    directly.

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
    and manual cleanup is error-prone. Terraform also produces outputs that later modules consume
    directly.

    EC2 is the exception: launching an instance manually first makes AMIs, key pairs, and security
    groups concrete before Terraform abstracts them away.

## Exercise — Provision with Terraform

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
