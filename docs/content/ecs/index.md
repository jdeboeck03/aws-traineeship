# ECS + ECR — Containers

This module containerises the Quarkus todo app, stores the image in a private registry, and runs
it on AWS as a managed service — no servers to patch, no SSH keys to manage.

Three steps in order:
1. **ECR** — create the registry, build the image, push it
2. **ECS** — run the container with Fargate; verify via a task's public IP
3. **ALB** — put a load balancer in front so the endpoint is stable

## Concepts

**Container image**
A snapshot of an application and all its dependencies packaged into a single, portable artefact.
The same image runs identically on a developer's laptop and in a cloud data centre. Images are
built from a `Dockerfile` and stored in a registry.

**ECR — Elastic Container Registry**
AWS's managed container image registry. Private by default: only principals with the right IAM
permissions can push or pull. Each repository stores images for one application; images are
addressed by tag (e.g. `latest`, a Git commit SHA).

**ECS — Elastic Container Service**
AWS's managed container orchestrator. You describe *what* to run (task definition) and *how many*
to keep running (service); ECS handles placement, restarts, and health checks. You never interact
with the underlying host.

**Fargate**
The serverless launch type for ECS. AWS provisions and manages the compute behind the scenes; you
pay per task's CPU and memory while it runs. The alternative, EC2 launch type, requires you to
manage a cluster of EC2 instances yourself. Fargate is the default choice for new workloads.

**Task definition**
An immutable blueprint for a container: which image to run, how much CPU and memory to allocate,
which environment variables and ports to expose, where to send logs, and which IAM roles to attach.
Every `terraform apply` that changes the task definition creates a new *revision* — the old one
is not deleted. The service is updated to run the latest revision.

**ECS service**
Keeps a desired number of task instances running. If a task crashes, the service starts a
replacement. When you update the task definition, the service replaces tasks one by one with the
new revision (rolling update by default).

**ALB — Application Load Balancer**
Distributes HTTP traffic across running tasks. Required for two reasons: a task's public IP
changes every time it is replaced, and ALB enables health checks so traffic only reaches healthy
tasks. ALB requires subnets in at least two Availability Zones for redundancy.

**Execution role vs. task role**
ECS uses two separate IAM roles — a subtle but important distinction:

| Role | Who uses it | What it needs |
|---|---|---|
| **Execution role** | The ECS *agent* (AWS infrastructure) | Pull image from ECR, write logs to CloudWatch |
| **Task role** | The *application code* inside the container | DynamoDB, SQS, SNS — whatever the app calls |

The execution role is identical across all services (AWS provides a managed policy for it). The
task role is application-specific and uses the same scoped permissions as the EC2 instance
profile did earlier — the model is the same, the attachment point is different.

!!! note "Free tier"
    ECS itself has no charge — you pay only for the Fargate compute (CPU + memory per second) and
    the ALB (per hour + per LCU). ECR charges for storage and data transfer. Verify current rates
    at [aws.amazon.com/fargate/pricing](https://aws.amazon.com/fargate/pricing) and
    [aws.amazon.com/ecr/pricing](https://aws.amazon.com/ecr/pricing).

---

!!! info "No manual exercise for this module"
    From VPC onwards, modules go straight to Terraform. ECS and ECR have many moving parts; the
    Terraform config is the clearest way to express them precisely.

    EC2 is the exception: launching an instance manually first makes AMIs, key pairs, and security
    groups concrete before Terraform abstracts them away.

---

## The app

The `app/` directory at the root of the repository contains the Quarkus todo application. It
exposes a simple REST API:

- `GET /todo` — list all todos
- `POST /todo` — create a todo (body: `{"title": "buy milk"}`)
- `GET /q/health` — health check endpoint (used by the ALB)

The app reads three environment variables set by the ECS task definition:

| Variable | Source |
|---|---|
| `DYNAMODB_TABLE_NAME` | `terraform output dynamodb_table_name` |
| `SQS_QUEUE_URL` | `terraform output sqs_queue_url` |
| `SNS_TOPIC_ARN` | `terraform output sns_topic_arn` |

Out of the box, it uses an in-memory repository (`InMemoryRepository`) so it starts cleanly
without AWS credentials. The DynamoDB, SQS, and SNS integrations are scaffolded but commented out
— you'll activate them in the DynamoDB and Messaging modules.

---

## Step 1 — ECR

### `terraform/ecr/`

```
terraform/ecr/
├── main.tf
├── variables.tf
└── outputs.tf
```

```hcl title="main.tf"
resource "aws_ecr_repository" "this" {
  name                 = var.name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = var.name
  }
}
```

`scan_on_push = true` runs a basic vulnerability scan on every pushed image at no extra cost.
`MUTABLE` tags allow re-pushing to the same tag (e.g. `latest`) — useful during development.

```hcl title="variables.tf"
variable "name" {
  description = "Name of the ECR repository."
  type        = string
}
```

```hcl title="outputs.tf"
output "repository_url" {
  description = "Full URL of the ECR repository (used in docker tag/push commands)."
  value       = aws_ecr_repository.this.repository_url
}
```

### Wire it into the full stack

Add the ECR module to `terraform/full-stack/main.tf`:

```hcl title="terraform/full-stack/main.tf"
module "ecr" {
  source = "../ecr"
  name   = var.name
}
```

Add the repository URL to `terraform/full-stack/outputs.tf`:

```hcl title="terraform/full-stack/outputs.tf"
output "ecr_repository_url" {
  description = "ECR repository URL (use this in docker tag/push commands)."
  value       = module.ecr.repository_url
}
```

### Apply

```shell
cd terraform/full-stack

terraform init   # picks up the ecr module
terraform plan
terraform apply
```

After apply, note `ecr_repository_url` — you'll need it to push the image.

### Build and push the image

Authenticate Docker to ECR (the token is valid for 12 hours):

=== "Linux / macOS"

    ```shell
    REPO_URL=$(terraform output -raw ecr_repository_url)
    REGION="eu-west-1"

    aws ecr get-login-password --region "$REGION" \
      | docker login --username AWS --password-stdin "$REPO_URL"
    ```

=== "Windows (PowerShell)"

    ```powershell
    $repoUrl = terraform output -raw ecr_repository_url
    $region  = "eu-west-1"

    aws ecr get-login-password --region $region `
      | docker login --username AWS --password-stdin $repoUrl
    ```

Build and tag the image from the `app/` directory:

=== "Linux / macOS"

    ```shell
    cd ../../app

    docker build -t "$REPO_URL:latest" .
    ```

=== "Windows (PowerShell)"

    ```powershell
    Set-Location ..\..\app

    docker build -t "${repoUrl}:latest" .
    ```

Push to ECR:

=== "Linux / macOS"

    ```shell
    docker push "$REPO_URL:latest"
    ```

=== "Windows (PowerShell)"

    ```powershell
    docker push "${repoUrl}:latest"
    ```

The push takes a couple of minutes on the first build (Maven downloads dependencies). Subsequent
pushes are faster because Docker caches the dependency layer.

!!! note "The image URI for Terraform"
    The full image URI you pushed is `<repo_url>:latest`. You'll need this in the next step as
    the `image_uri` variable. Copy it from the `ecr_repository_url` output with `:latest` appended.

---

## Step 2 — ECS

### `terraform/ecs/`

```
terraform/ecs/
├── main.tf
├── variables.tf
└── outputs.tf
```

The module creates all ECS resources. The key sections of `main.tf`:

```hcl title="main.tf — execution role"
resource "aws_iam_role" "execution" {
  name = "${var.name}-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${var.name}-ecs-execution-role" }
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
```

The execution role uses the AWS-managed policy `AmazonECSTaskExecutionRolePolicy` — it grants ECR
pull and CloudWatch Logs write permissions. You don't write this policy yourself.

```hcl title="main.tf — task role"
resource "aws_iam_role" "task" {
  name = "${var.name}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${var.name}-ecs-task-role" }
}

resource "aws_iam_policy" "task" {
  name = "${var.name}-ecs-task-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem", "dynamodb:GetItem", "dynamodb:DeleteItem",
                    "dynamodb:Query", "dynamodb:Scan"]
        Resource = var.dynamodb_table_arn
      },
      {
        Effect   = "Allow"
        Action   = ["sqs:SendMessage", "sqs:ReceiveMessage",
                    "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
        Resource = var.sqs_queue_arn
      },
      {
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = var.sns_topic_arn
      },
    ]
  })

  tags = { Name = "${var.name}-ecs-task-policy" }
}

resource "aws_iam_role_policy_attachment" "task" {
  role       = aws_iam_role.task.name
  policy_arn = aws_iam_policy.task.arn
}
```

The task role is the container equivalent of the EC2 instance profile. The trust principal
(`ecs-tasks.amazonaws.com`) is the only difference from the EC2 role — the permission model is
identical.

```hcl title="main.tf — task definition"
resource "aws_ecs_task_definition" "this" {
  family                   = var.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([{
    name      = var.name
    image     = var.image_uri
    essential = true

    portMappings = [{
      containerPort = var.container_port
      hostPort      = var.container_port
      protocol      = "tcp"
    }]

    environment = [
      { name = "DYNAMODB_TABLE_NAME", value = var.dynamodb_table_name },
      { name = "SQS_QUEUE_URL",       value = var.sqs_queue_url },
      { name = "SNS_TOPIC_ARN",       value = var.sns_topic_arn },
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = "/ecs/${var.name}"
        "awslogs-region"        = "eu-west-1"
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])

  tags = { Name = var.name }
}
```

Environment variables are the standard way to inject runtime configuration into containers.
The app reads `DYNAMODB_TABLE_NAME`, `SQS_QUEUE_URL`, and `SNS_TOPIC_ARN` via
`System.getenv()` — no hardcoded values, no config files to rebuild.

```hcl title="main.tf — cluster and service"
resource "aws_ecs_cluster" "this" {
  name = "${var.name}-cluster"
  tags = { Name = "${var.name}-cluster" }
}

resource "aws_ecs_service" "this" {
  name            = "${var.name}-service"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.service.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.this.arn
    container_name   = var.name
    container_port   = var.container_port
  }

  depends_on = [aws_lb_listener.http]

  tags = { Name = "${var.name}-service" }
}
```

`depends_on = [aws_lb_listener.http]` prevents a race condition: without it Terraform may create
the service before the ALB listener exists, causing the first health check to fail and the task
to cycle.

### Wire it into the full stack

ALB requires subnets in at least two Availability Zones. The VPC module creates one subnet in
`eu-west-1a`. Add a second one directly in `terraform/full-stack/main.tf`:

```hcl title="terraform/full-stack/main.tf — second subnet"
# ALB requires subnets in at least two AZs. The VPC module creates one subnet
# in eu-west-1a; this second subnet in eu-west-1b is added when ECS is introduced.
resource "aws_subnet" "public_b" {
  vpc_id                  = module.vpc.vpc_id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "${var.region}b"
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.name}-public-subnet-b"
  }
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = module.vpc.public_route_table_id
}
```

The VPC module exposes `public_route_table_id` for exactly this purpose — the second subnet
reuses the same internet gateway and route table, so it gets the same public routing.

Add the ECS module call:

```hcl title="terraform/full-stack/main.tf — ECS module"
module "ecs" {
  source = "../ecs"
  name   = var.name

  vpc_id     = module.vpc.vpc_id
  subnet_ids = [module.vpc.public_subnet_id, aws_subnet.public_b.id]

  image_uri      = var.image_uri
  container_port = 8080

  dynamodb_table_name = module.dynamodb.table_name
  dynamodb_table_arn  = module.dynamodb.table_arn
  sqs_queue_url       = module.sqs.queue_url
  sqs_queue_arn       = module.sqs.queue_arn
  sns_topic_arn       = module.sns.topic_arn
}
```

Add `image_uri` to `terraform/full-stack/variables.tf`:

```hcl title="terraform/full-stack/variables.tf"
variable "image_uri" {
  description = "Full ECR image URI including tag, e.g. 123456789.dkr.ecr.eu-west-1.amazonaws.com/your-name:latest."
  type        = string
}
```

Add `image_uri` to `terraform/full-stack/terraform.tfvars`:

```hcl title="terraform/full-stack/terraform.tfvars"
image_uri = "<ecr_repository_url>:latest"
```

Replace `<ecr_repository_url>` with the value from `terraform output ecr_repository_url`.

Add the ALB URL to `terraform/full-stack/outputs.tf`:

```hcl title="terraform/full-stack/outputs.tf"
output "alb_dns_name" {
  description = "URL of the Application Load Balancer."
  value       = module.ecs.alb_dns_name
}
```

### Apply

```shell
cd terraform/full-stack

terraform init   # picks up the ecs module
terraform plan
terraform apply
```

ECS provisioning takes 2–3 minutes — Fargate needs to pull the image and the ALB health check
must pass before the service is considered stable.

### Verify

Open the ALB endpoint in a browser or curl it:

=== "Linux / macOS"

    ```shell
    ALB=$(terraform output -raw alb_dns_name)

    curl "$ALB/todo"

    curl -X POST "$ALB/todo" \
      -H "Content-Type: application/json" \
      -d '{"title": "buy milk"}'

    curl "$ALB/todo"
    ```

=== "Windows (PowerShell)"

    ```powershell
    $alb = terraform output -raw alb_dns_name

    Invoke-RestMethod -Uri "$alb/todo"

    Invoke-RestMethod -Uri "$alb/todo" -Method Post `
      -ContentType "application/json" `
      -Body '{"title": "buy milk"}'

    Invoke-RestMethod -Uri "$alb/todo"
    ```

The first `GET /todo` returns an empty list. After the `POST`, the second `GET` returns
`[{"title":"buy milk"}]` — stored in memory for now. You'll wire it to DynamoDB next.

!!! note "Task restarts reset in-memory state"
    The `InMemoryRepository` stores todos in the JVM heap. A task restart (deploy, health-check
    failure, scale-in) wipes the list. This is expected — it's the motivation for using DynamoDB.

### Activating the DynamoDB integration

Open `app/src/main/java/be/axxes/traineeship/todo/repository/DynamoDbRepository.java`, remove
the `//` comment from `@ApplicationScoped`, and add `@ApplicationScoped` to nothing — then remove
`@ApplicationScoped` from `InMemoryRepository`. Rebuild and push:

=== "Linux / macOS"

    ```shell
    cd ../../app
    docker build -t "$REPO_URL:latest" .
    docker push "$REPO_URL:latest"
    ```

=== "Windows (PowerShell)"

    ```powershell
    Set-Location ..\..\app
    docker build -t "${repoUrl}:latest" .
    docker push "${repoUrl}:latest"
    ```

Force a new deployment so ECS pulls the updated image:

=== "Linux / macOS"

    ```shell
    cd ../terraform/full-stack
    aws ecs update-service \
      --cluster "$(terraform output -raw cluster_name 2>/dev/null || echo "${var.name}-cluster")" \
      --service "$(terraform output -raw service_name 2>/dev/null || echo "${var.name}-service")" \
      --force-new-deployment
    ```

=== "Windows (PowerShell)"

    ```powershell
    Set-Location ..\terraform\full-stack
    aws ecs update-service `
      --cluster "<your-name>-cluster" `
      --service "<your-name>-service" `
      --force-new-deployment
    ```

!!! note "Why force-new-deployment?"
    The task definition's `image` is still `<repo_url>:latest` — the string didn't change, so
    Terraform doesn't detect a difference and won't create a new revision. `--force-new-deployment`
    tells ECS to replace tasks with the same task definition, pulling the latest image from ECR.
    In production you'd use commit-SHA tags instead of `latest` so Terraform can detect changes.

### Clean up

```shell
terraform destroy
```

!!! warning "ECR images are not destroyed"
    `terraform destroy` deletes the ECR *repository* resource, but only if it is empty. If you
    pushed images, `destroy` will fail with `RepositoryNotEmptyException`. Delete all images first
    in the console (ECR → repository → select all → Delete) or with the CLI:

    === "Linux / macOS"

        ```shell
        REPO=$(terraform output -raw ecr_repository_url | cut -d/ -f2-)
        aws ecr batch-delete-image \
          --repository-name "$REPO" \
          --image-ids imageTag=latest
        ```

    === "Windows (PowerShell)"

        ```powershell
        $repo = (terraform output -raw ecr_repository_url).Split("/", 2)[1]
        aws ecr batch-delete-image `
          --repository-name $repo `
          --image-ids imageTag=latest
        ```

---

## Key takeaways

- ECR is a private Docker registry — authenticate with `ecr get-login-password` before pushing;
  the token is valid for 12 hours.
- Fargate runs containers without managing EC2 hosts — you define CPU, memory, and the image;
  AWS handles placement and restarts.
- ECS uses **two** IAM roles: the execution role (for AWS infrastructure — pull image, write logs)
  and the task role (for application code — DynamoDB, SQS, SNS). Both trust `ecs-tasks.amazonaws.com`.
- Task definitions are immutable — every change creates a new revision. ECS services roll to the
  latest revision on the next deployment.
- ALB requires subnets in at least **two Availability Zones**. A second public subnet is added in
  `eu-west-1b` directly in `full-stack/main.tf` when ECS is introduced — the VPC module itself
  is unchanged.
- Pushing `:latest` and re-deploying requires `--force-new-deployment` because Terraform only
  detects changes to the task definition string, not to the image content in ECR.
- ECR repositories must be empty before `terraform destroy` can delete them.
