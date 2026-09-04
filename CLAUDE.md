# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Purpose

My own AWS traineeship, based on the Axxes course structure from Rob's 2026 traineeship (see parent CLAUDE.md for reference).

## AWS Configuration

- SSO Start URL: `https://axxes.awsapps.com/start/#/`
- SSO Region: `eu-west-1`
- Testing account: `sandbox-2024` (ID: `211125550721`)
- Production account: `traineeship-2026` (ID: `313160010160`)
- Default region: `eu-west-1`
- Identity provider: Azure AD — trainees log in with their own AD users
- Model: all trainees share one AWS account

<!-- Fill in as resources are created -->
- DynamoDB table: (your table name)
- SQS queue URL: (your queue URL)

## Infrastructure tooling

**Terraform** (not CloudFormation). Rob's reference uses CloudFormation — use it to understand what
resources to create, but write Terraform equivalents here. Each service module has a `terraform/`
directory alongside its docs.

## Documentation conventions

New service module doc? Start from `MODULE_TEMPLATE.md` (repo root, not published to the docs
site) — it's the skeleton structure plus a pre-publish checklist distilled from the rules below.
These rules are the "why"; the template is the copy-paste starting point.

- **Cross-shell commands.** Every documented shell command must work when copy-pasted into **both**
  bash (Linux/macOS) and Windows PowerShell — trainees use both. Use mkdocs content tabs
  (`=== "Linux / macOS"` / `=== "Windows (PowerShell)"`, enabled via `pymdownx.tabbed` in
  `mkdocs.yml`) whenever a command needs line continuation, variable assignment, or other
  shell-specific syntax (bash `\` + `$(...)` vs. PowerShell `` ` `` + `$var = ...`). A single-line
  command with no shell-specific syntax doesn't need tabs.
- **No stale hardcoded values.** AMI IDs, and other values that go stale as AWS ships updates,
  should be looked up dynamically (SSM parameter, CLI query, Terraform data source) rather than
  hardcoded — see `terraform/ec2` for the pattern. SSM parameter values come back marked
  `sensitive` by default even when the underlying value isn't secret (e.g. a public AMI ID) — use
  Terraform's `nonsensitive()` so it's still visible in plan/apply output.
- **Tag everything, including side-effect resources.** Every resource needs `Project`/`Owner`/
  `Contact` tags (see `docs/content/tagging/index.md`). Terraform: one `default_tags` block on the
  provider, not per-resource. Console/CLI: auxiliary resources created as a side effect (e.g. a
  security group the console wizard creates alongside an instance) do **not** inherit the "main"
  resource's tags — call this out explicitly and give it its own tagging step.
- **Cleanup must cover every resource, not just the obvious one.** Terminating/deleting the
  headline resource often doesn't remove things it depended on (security groups, key pairs, ...).
  Document explicit teardown for each one, with the actual CLI command — not just "delete it in the
  console." When two exercises for the same module reuse a naming convention (e.g. Exercise 1's
  manual key pair and Exercise 2's Terraform key pair both named `<your-name>-key`), flag the
  collision risk and add a troubleshooting note with the exact error text for when cleanup is
  skipped.
- **Manual exercise: EC2 only.** EC2 has an explicit Exercise 1 (console + CLI) because launching
  an instance manually first makes AMIs, key pairs, and security groups concrete. From VPC onwards,
  modules skip the manual exercise and go straight to Terraform — infrastructure wiring resources
  (subnets, route tables, IGWs, IAM roles, ...) don't build meaningful intuition from manual
  creation, and the cleanup steps multiply the risk of leftover resources. Replace Exercise 1 with
  an `!!! info "No manual exercise for this module"` callout explaining the rationale (see
  `docs/content/networking/index.md` for the pattern).
- **Terraform is copy-along, not an exercise.** Show the Terraform code directly — no collapsed
  hints or solution blocks. This is an AWS traineeship, not a Terraform course; trainees should
  spend their time understanding AWS concepts, not wrestling with HCL syntax. After showing each
  file, add a short paragraph explaining the non-obvious decisions (why a resource exists, why
  ordering matters, a common gotcha) — explain the *why*, not the *what*. See
  `docs/content/networking/index.md` for the pattern.
- **Variable hygiene.** Personal per-trainee values (`name`, `owner`, `contact`, `project`, ...)
  are required variables with no default. Once a module needs more than ~2 required variables,
  point at the `terraform.tfvars` pattern (`terraform-fundamentals/index.md`) instead of a growing
  `-var=...` flag chain.
- **Verify live, don't recall from memory.** Any AWS-specific claim in the docs — pricing, free-tier
  eligibility, current AMI/resource metadata, exact error text — should be checked against the real
  account (AWS CLI/console) before publishing, not stated from memory. These change over time and
  are easy to get subtly wrong. Same for new markdown/mkdocs syntax: check the built HTML
  (`mkdocs build --strict`, then inspect `site/`) rather than assuming an extension is enabled.

## Security tooling

This repo is public and deploys to GitHub Pages, so secret-leak prevention is layered:

1. **GitHub secret scanning + push protection** — enabled at the repo level (Settings → Code
   security and analysis). Server-side; nothing to install.
2. **Local pre-commit hook** (`.pre-commit-config.yaml`, gitleaks). This file is committed, but the
   actual git hook (`.git/hooks/pre-commit`) is **not** — it's outside version control. After
   cloning, run `pip install pre-commit && pre-commit install` (and `scoop install gitleaks` or
   equivalent) to activate it. Without this step, commits on a fresh clone aren't scanned locally.
3. **Claude Code hook** (`.claude/settings.json` + `.claude/hooks/scan-git-secrets.sh`) — scans
   before `git commit`/`git push` specifically when Claude Code is driving the command. Covers
   `git push` (which pre-commit hooks don't see) and `--no-verify` bypasses of layer 2. Fails open
   (allows the command) if `gitleaks` or `jq` isn't on `PATH`.
4. **No static AWS credentials anywhere in this project** — every AWS interaction goes through SSO
   profiles (`aws configure sso`, see `getting-started/index.md`), never long-lived access keys.
   This matters more than any scanner: AWS secret access keys have no fixed prefix (unlike access
   key IDs, which start `AKIA`/`ASIA` and are reliably pattern-matched), so generic secret scanners
   rely on entropy heuristics that can miss them — confirmed by testing during setup, where
   gitleaks' generic-api-key rule caught some random test values but not others. Treat scanning as
   a safety net, not a guarantee; the SSO-only model is the actual structural protection.

## Branch strategy

`main` is the only branch that matters for day-to-day work — documentation changes and Terraform
additions always go here. GitHub Pages is deployed from `main`.

`checkpoint/NN-topic` branches exist for trainers who want to test the stack from a clean starting
point without commenting things out of `main`. Each checkpoint is cumulative:

| Branch | Stack |
|--------|-------|
| `checkpoint/01-ec2` | EC2 only (default VPC) |
| `checkpoint/02-networking` | + custom VPC + SSH security group |
| `checkpoint/03-s3` | + S3 |
| `checkpoint/04-dynamodb` | + DynamoDB |
| `checkpoint/05-iam` | + IAM (S3 + DynamoDB policies; SQS/SNS not yet wired) + `app/` (nothing activated) |
| `checkpoint/05a-app-dynamodb` | same Terraform as 05-iam; app with DynamoDB activated |
| `checkpoint/05b-app-s3` | same Terraform as 05-iam; app with DynamoDB + S3 backup activated |
| `checkpoint/06-messaging` | + SQS + SNS (IAM gets full policies); app in 05b state |
| `checkpoint/07-ecs` | + ECR + ECS (with S3 env var + PutObject policy) + second public subnet; app in 05b state |
| `checkpoint/08-lambda` | + Lambda = full stack; app in 05b state |

**Checkpoint branches do not contain `docs/`.** Documentation lives on `main` only — never edit
docs on a checkpoint branch.

**Checkpoint branches only contain the terraform module directories introduced up to that point.**
`terraform/full-stack/` is always present; individual module directories (`terraform/ec2/`,
`terraform/vpc/`, etc.) appear from their introducing checkpoint onwards and are absent before it.
`checkpoint/01-ec2` contains only `terraform/ec2/` + `terraform/full-stack/`;
`checkpoint/02-networking` adds `terraform/vpc/`; and so on.

**Updating a checkpoint branch** (e.g. after fixing a bug in `terraform/ec2`):

```bash
git checkout checkpoint/01-ec2
# make the fix
git add terraform/ec2/
git commit -m "fix: ..."
git push origin checkpoint/01-ec2
git checkout main
```

Repeat for any later checkpoints that are affected by the same fix.

**After every change on `main`, always ask: do any checkpoint branches need updating?**
Use this checklist:

- Did you change anything under `terraform/`? → update every checkpoint branch that includes that
  module directory and all later ones (they're cumulative).
- Did you change `docs/`, `mkdocs.yml`, or any repo-root file? → no checkpoint update needed
  (`docs/` doesn't exist on checkpoint branches).
- Did you change `terraform/full-stack/`? → update every checkpoint branch (it's always present).

If checkpoint branches do need updating, apply the fix to each affected branch in order (earliest
first) and push each one before moving to the next.

## Structure

- `docs/` — notes and documentation per AWS service
- `PLAN.md` — module plan and scope for the traineeship day (not published to the docs site)
- `MODULE_TEMPLATE.md` — skeleton + checklist for writing a new service module's docs (not
  published to the docs site)
- `app/` — Quarkus application (DynamoDB + SQS SDK integration)
- `terraform/` — Terraform root module (full stack, built up incrementally)
