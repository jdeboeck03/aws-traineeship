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

- Every documented shell command must work when copy-pasted into **both** bash (Linux/macOS) and
  Windows PowerShell — trainees use both. Use mkdocs content tabs
  (`=== "Linux / macOS"` / `=== "Windows (PowerShell)"`, enabled via `pymdownx.tabbed` in
  `mkdocs.yml`) whenever a command needs line continuation, variable assignment, or other
  shell-specific syntax (bash `\` + `$(...)` vs. PowerShell `` ` `` + `$var = ...`). A single-line
  command with no shell-specific syntax doesn't need tabs.
- AMI IDs, and other values that go stale as AWS ships updates, should be looked up dynamically
  (SSM parameter, CLI query, Terraform data source) rather than hardcoded — see `terraform/ec2` for
  the pattern.

## Structure

- `docs/` — notes and documentation per AWS service
- `PLAN.md` — module plan and scope for the traineeship day (not published to the docs site)
- `app/` — Quarkus application (DynamoDB + SQS SDK integration)
- `terraform/` — Terraform root module (full stack, built up incrementally)
