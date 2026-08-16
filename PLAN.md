# Traineeship Plan

This page describes the intended scope and module order for this AWS traineeship.

## Infrastructure tooling

All infrastructure in this traineeship is created with **Terraform** instead of CloudFormation.
Rob's reference uses CloudFormation templates — those are useful for understanding what resources to
create, but the Terraform equivalents will be written from scratch here.

Each service module will have a `terraform/` directory alongside its documentation containing the
relevant `.tf` files.

## Status of existing content

| Topic | Status | Notes |
|---|---|---|
| AWS Console access | Done | `getting-started/index.md` |
| AWS CLI installation & SSO | Done | `getting-started/index.md` |
| AWS CLI — setting a default profile | Done | `getting-started/index.md` |
| Tagging convention (Project/Owner/Contact) | Done | `tagging/index.md` |
| Terraform fundamentals (concepts, workflow, state) | Done | `terraform-fundamentals/index.md` |

The getting-started section is complete and ready to be delivered. Tagging and Terraform
Fundamentals are cross-cutting sections delivered before Module 1 (EC2), same tier as
getting-started — every later module's Terraform should follow the `default_tags` pattern
introduced there.

## Planned modules

The modules below are ordered roughly as they would be introduced during the day.
Services are picked from Rob's traineeship for their developer relevance — data-focused services
(Glue, Athena, EMR, SageMaker, QuickSight) are omitted as they are less relevant to the
typical backend developer audience.

When writing up the next module's docs, start from `MODULE_TEMPLATE.md` — the structure, tagging,
cleanup, cross-shell, and hints/solution conventions it captures came out of building EC2 and apply
to every module below.

---

### 1. EC2 — Virtual Machines

**Why:** Foundational building block. Everyone should understand what a VM on AWS looks like before
moving to higher abstractions.

**Topics:**
- Launch an EC2 instance (AMI, instance type, key pair, security group)
- Connect via SSH
- Terraform: `aws_instance`, `aws_key_pair`, `aws_security_group`

---

### 2. Networking — VPC

**Why:** Required context for ECS and understanding security groups vs. public/private subnets.

**Topics:**
- VPC, subnets, internet gateway, route tables
- Public vs. private subnets
- Security groups as stateful firewalls
- Terraform: `aws_vpc`, `aws_subnet`, `aws_internet_gateway`, `aws_route_table`, `aws_security_group`

---

### 3. S3 — Object Storage

**Why:** Ubiquitous in every AWS architecture. Developers interact with S3 constantly.

**Topics:**
- Buckets, objects, presigned URLs
- Static website hosting
- Bucket policies and access control
- Terraform: `aws_s3_bucket`, `aws_s3_bucket_policy`, `aws_s3_object`

---

### 4. IAM — Identity and Access Management

**Why:** Cuts across everything. Understanding roles, policies, and least-privilege is essential
before touching ECS, Lambda, or any SDK integration.

**Topics:**
- Users, groups, roles, policies
- Instance profiles and task roles
- Inline vs. managed policies
- Terraform: `aws_iam_role`, `aws_iam_policy`, `aws_iam_role_policy_attachment`

---

### 5. DynamoDB — NoSQL Database

**Why:** The primary database used by the Quarkus app. Highly relevant for developers building
serverless or cloud-native apps.

**Topics:**
- Tables, partition keys, sort keys
- Read/write capacity vs. on-demand
- SDK integration from the Quarkus app
- Terraform: `aws_dynamodb_table`

---

### 6. SQS + SNS — Messaging

**Why:** Core event-driven pattern. SQS for queues (at-least-once delivery), SNS for fan-out.
Both are used in the final application.

**Topics:**
- SQS: sending, receiving, deleting messages; visibility timeout; dead-letter queues
- SNS: topics, subscriptions, SNS → SQS fan-out
- SDK integration from the Quarkus app
- Terraform: `aws_sqs_queue`, `aws_sns_topic`, `aws_sns_topic_subscription`

---

### 7. ECS + ECR — Containers

**Why:** The dominant way to run containerised workloads on AWS without managing servers.
Covers the full journey: build → push → run.

**Topics:**
- ECR: building and pushing a Docker image
- ECS Fargate: cluster, task definition, service
- Load balancer integration (ALB)
- CloudMap service discovery
- Terraform: `aws_ecr_repository`, `aws_ecs_cluster`, `aws_ecs_task_definition`,
  `aws_ecs_service`, `aws_lb`, `aws_lb_listener`, `aws_lb_target_group`

---

### 8. Lambda — Serverless Functions

**Why:** Serverless is everywhere. Practical for scheduled jobs, event consumers, and glue code.

**Topics:**
- Function handlers, runtimes, environment variables
- Triggers: schedule (EventBridge), SQS event source mapping
- IAM execution role
- Terraform: `aws_lambda_function`, `aws_lambda_event_source_mapping`,
  `aws_cloudwatch_event_rule`, `aws_cloudwatch_event_target`

---

### 9. CloudWatch — Monitoring

**Why:** You can't operate what you can't observe. Structured logging and metrics from ECS and
Lambda land here by default.

**Topics:**
- Log groups and log streams
- Metrics and alarms
- Dashboards
- Terraform: `aws_cloudwatch_log_group`, `aws_cloudwatch_metric_alarm`

---

### 10. Putting it all together

**Why:** Cement the knowledge by wiring all services into a single architecture.

**Architecture:**

```
EventBridge (schedule)
    └─► Lambda
            └─► HTTP → ECS Service (via CloudMap / ALB)
                            ├─► DynamoDB
                            └─► SQS ──► SNS ──► SQS subscribers

All services → CloudWatch Logs + Metrics
```

**Deliverable:** A single Terraform root module (`terraform/`) that provisions the entire stack.
The Quarkus app in `app/` integrates with DynamoDB and SQS via the AWS SDK.

**Remote state:** This is also where we introduce an S3 + DynamoDB remote backend (state bucket +
lock table), once S3 and DynamoDB have already been taught as services in their own right. Not
introduced earlier — every prior module's state is personal, short-lived, and destroyed same-day,
so there's no real collaboration/locking problem to motivate it yet, and a shared backend needs
bootstrapping outside the config it locks plus a per-trainee state key to avoid collisions.

---

## Explicitly out of scope

The following services from Rob's traineeship are skipped as they target data engineers rather
than backend developers:

- Glue
- Athena
- EMR
- SageMaker
- QuickSight
- Ansible provisioning
