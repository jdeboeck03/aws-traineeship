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
- **Terraform exercises are hints-first, not copy-paste.** State the task and requirements, list
  hints under a collapsed `??? question "Hints"` block, and put the full working module under a
  collapsed `??? example "Show solution"` block (via `pymdownx.details`, already enabled in
  `mkdocs.yml`) — trainees write their own module and only reveal the reference solution if stuck
  or to check their work. See `docs/content/ec2/index.md` Exercise 2 for the pattern. Command
  workflow shown outside the collapsed blocks (variables, `init`/`plan`/`apply`/`destroy`) applies
  regardless of whose implementation the trainee wrote, so it stays visible by default. Paste the
  solution code inline in full — **don't link the public GitHub repo** for it: the code's already
  there, and a repo link lets trainees browse ahead into modules not taught yet.
- **Variable hygiene.** Personal per-trainee values (`name`, `owner`, `contact`, `project`, ...)
  are required variables with no default. Once a module needs more than ~2 required variables,
  point at the `terraform.tfvars` pattern (`terraform-fundamentals/index.md`) instead of a growing
  `-var=...` flag chain.
- **Verify live, don't recall from memory.** Any AWS-specific claim in the docs — pricing, free-tier
  eligibility, current AMI/resource metadata, exact error text — should be checked against the real
  account (AWS CLI/console) before publishing, not stated from memory. These change over time and
  are easy to get subtly wrong. Same for new markdown/mkdocs syntax: check the built HTML
  (`mkdocs build --strict`, then inspect `site/`) rather than assuming an extension is enabled.

## Structure

- `docs/` — notes and documentation per AWS service
- `PLAN.md` — module plan and scope for the traineeship day (not published to the docs site)
- `MODULE_TEMPLATE.md` — skeleton + checklist for writing a new service module's docs (not
  published to the docs site)
- `app/` — Quarkus application (DynamoDB + SQS SDK integration)
- `terraform/` — Terraform root module (full stack, built up incrementally)
