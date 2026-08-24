# ECS + ECR — Containers

[Amazon ECS](https://aws.amazon.com/ecs/) is a managed container orchestrator. You describe what
to run (task definition) and how many copies to keep alive (service); ECS handles placement and
restarts. The **Fargate** launch type removes the need to manage EC2 hosts — you pay per task's
CPU and memory while it runs.

ECS uses two IAM roles per service: the **execution role** (AWS infrastructure — pulls the image
from ECR, writes logs to CloudWatch) and the **task role** (your application code — DynamoDB, SQS,
SNS). Both trust `ecs-tasks.amazonaws.com`; both are written explicitly in Terraform.

## Step 1 — ECR

### `terraform/ecr/`

```hcl title="main.tf"
resource "aws_ecr_repository" "this" {
  name                 = var.name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = { Name = var.name }
}
```

```hcl title="variables.tf"
variable "name" {
  type = string
}
```

```hcl title="outputs.tf"
output "repository_url" {
  value = aws_ecr_repository.this.repository_url
}
```

### Wire it into the full stack

```hcl title="terraform/full-stack/main.tf"
module "ecr" {
  source = "../ecr"
  name   = var.name
}
```

```hcl title="terraform/full-stack/outputs.tf"
output "ecr_repository_url" {
  value = module.ecr.repository_url
}
```

### Apply, build and push

```shell
cd terraform/full-stack
terraform init
terraform apply
```

Authenticate Docker to ECR, then build and push from the `app/` directory:

=== "Linux / macOS"

    ```shell
    REPO_URL=$(terraform output -raw ecr_repository_url)

    aws ecr get-login-password --region eu-west-1 \
      | docker login --username AWS --password-stdin "$REPO_URL"

    cd ../../app
    docker build -t "$REPO_URL:latest" .
    docker push "$REPO_URL:latest"
    ```

=== "Windows (PowerShell)"

    ```powershell
    $repoUrl = terraform output -raw ecr_repository_url

    aws ecr get-login-password --region eu-west-1 `
      | docker login --username AWS --password-stdin $repoUrl

    Set-Location ..\..\app
    docker build -t "${repoUrl}:latest" .
    docker push "${repoUrl}:latest"
    ```

---

## Step 2 — ECS + ALB

### `terraform/ecs/`

```hcl title="main.tf"
data "aws_region" "current" {}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/ecs/${var.name}"
  retention_in_days = 7
  tags = { Name = "${var.name}-logs" }
}

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

resource "aws_ecs_cluster" "this" {
  name = "${var.name}-cluster"
  tags = { Name = "${var.name}-cluster" }
}

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
        "awslogs-region"        = data.aws_region.current.name
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])

  tags = { Name = var.name }
}

resource "aws_security_group" "alb" {
  name        = "${var.name}-alb-sg"
  description = "Allow HTTP inbound to the ALB."
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name}-alb-sg" }
}

resource "aws_security_group" "service" {
  name        = "${var.name}-service-sg"
  description = "Allow traffic from the ALB to the container."
  vpc_id      = var.vpc_id

  ingress {
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name}-service-sg" }
}

resource "aws_lb" "this" {
  name               = "${var.name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.subnet_ids
  tags = { Name = "${var.name}-alb" }
}

resource "aws_lb_target_group" "this" {
  name        = "${var.name}-tg"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path = "/q/health"
  }

  tags = { Name = "${var.name}-tg" }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
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

  # Prevents a race where the service starts before the listener exists.
  depends_on = [aws_lb_listener.http]

  tags = { Name = "${var.name}-service" }
}
```

```hcl title="variables.tf"
variable "name"               { type = string }
variable "vpc_id"             { type = string }
variable "subnet_ids"         { type = list(string) }
variable "image_uri"          { type = string }
variable "container_port"     { type = number; default = 8080 }
variable "dynamodb_table_name"{ type = string }
variable "dynamodb_table_arn" { type = string }
variable "sqs_queue_url"      { type = string }
variable "sqs_queue_arn"      { type = string }
variable "sns_topic_arn"      { type = string }
```

```hcl title="outputs.tf"
output "alb_dns_name" { value = aws_lb.this.dns_name }
```

### Wire it into the full stack

ALB requires subnets in at least two Availability Zones. Add a second public subnet in
`terraform/full-stack/main.tf` alongside the VPC module:

```hcl title="terraform/full-stack/main.tf"
resource "aws_subnet" "public_b" {
  vpc_id                  = module.vpc.vpc_id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "${var.region}b"
  map_public_ip_on_launch = true
  tags = { Name = "${var.name}-public-subnet-b" }
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = module.vpc.public_route_table_id
}

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

Add `image_uri` to `terraform/full-stack/variables.tf` and `terraform.tfvars`:

```hcl title="terraform/full-stack/variables.tf"
variable "image_uri" {
  description = "Full ECR image URI including tag."
  type        = string
}
```

```hcl title="terraform.tfvars"
image_uri = "<ecr_repository_url>:latest"
```

Add to `terraform/full-stack/outputs.tf`:

```hcl title="terraform/full-stack/outputs.tf"
output "alb_dns_name" {
  value = module.ecs.alb_dns_name
}
```

### Apply and verify

```shell
cd terraform/full-stack
terraform init
terraform apply
```

ECS provisioning takes 2–3 minutes while Fargate pulls the image and the ALB health check passes.

=== "Linux / macOS"

    ```shell
    ALB=$(terraform output -raw alb_dns_name)
    curl "$ALB/todo"
    ```

=== "Windows (PowerShell)"

    ```powershell
    $alb = terraform output -raw alb_dns_name
    Invoke-RestMethod -Uri "$alb/todo"
    ```

---

## Clean up

```shell
terraform destroy
```

!!! warning "Delete ECR images before destroying"
    `terraform destroy` fails with `RepositoryNotEmptyException` if the repository contains images.
    Delete them first:

    === "Linux / macOS"

        ```shell
        REPO=$(terraform output -raw ecr_repository_url | cut -d/ -f2-)
        aws ecr batch-delete-image --repository-name "$REPO" --image-ids imageTag=latest
        ```

    === "Windows (PowerShell)"

        ```powershell
        $repo = (terraform output -raw ecr_repository_url).Split("/", 2)[1]
        aws ecr batch-delete-image --repository-name $repo --image-ids imageTag=latest
        ```
