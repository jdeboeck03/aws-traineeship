terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region  = var.region
  profile = "traineeship"

  default_tags {
    tags = {
      Project = var.project
      Owner   = var.owner
      Contact = var.contact
    }
  }
}

module "vpc" {
  source  = "../vpc"
  name    = var.name
  owner   = var.owner
  contact = var.contact
  project = var.project
  region  = var.region
}

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

resource "aws_security_group" "ssh" {
  name        = "${var.name}-ssh-sg"
  description = "Allow SSH inbound"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name}-ssh-sg"
  }
}

module "dynamodb" {
  source = "../dynamodb"
  name   = var.name
}

module "sqs" {
  source = "../sqs"
  name   = var.name
}

module "sns" {
  source    = "../sns"
  name      = var.name
  queue_arn = module.sqs.queue_arn
  queue_url = module.sqs.queue_url
}

module "iam" {
  source             = "../iam"
  name               = var.name
  bucket_name        = var.bucket_name
  dynamodb_table_arn = module.dynamodb.table_arn
  sqs_queue_arn      = module.sqs.queue_arn
  sns_topic_arn      = module.sns.topic_arn
}

module "ec2" {
  source               = "../ec2"
  name                 = var.name
  owner                = var.owner
  contact              = var.contact
  project              = var.project
  region               = var.region
  subnet_id            = module.vpc.public_subnet_id
  security_group_ids   = [aws_security_group.ssh.id]
  iam_instance_profile = module.iam.instance_profile_name
}

module "s3" {
  source      = "../s3"
  bucket_name = var.bucket_name
}

module "ecr" {
  source = "../ecr"
  name   = var.name
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
  s3_bucket_name      = module.s3.bucket_name
  s3_bucket_arn       = module.s3.bucket_arn
}

module "lambda" {
  source = "../lambda"
  name   = var.name

  sns_topic_arn = module.sns.topic_arn
  sqs_queue_arn = module.sqs.queue_arn
}
