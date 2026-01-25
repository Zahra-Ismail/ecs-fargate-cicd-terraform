################################
# Terraform & Provider
################################
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "eu-north-1"
}

################################
# Variables
################################
variable "project_name" {
  default = "ecs-fargate-cicd-terraform"
}

variable "github_repo" {
  description = "GitHub repo in OWNER/REPO format"
  type        = string
}

variable "container_image" {
  description = "Docker image URI pushed to ECR"
  type        = string
}

variable "container_port" {
  default = 8080
}

locals {
  app_log_group = "/ecs/${var.project_name}"
  cluster_name  = "${var.project_name}-cluster"
}

################################
# Existing resources (REUSE)
################################

data "aws_ecr_repository" "app" {
  name = var.project_name
}

data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

data "aws_cloudwatch_log_group" "app" {
  name = local.app_log_group
}

data "aws_iam_role" "github_action" {
  name = "Github_Action"
}

resource "aws_iam_role_policy_attachment" "github_admin" {
  role       = data.aws_iam_role.github_action.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

################################
# VPC - USE DEFAULT VPC
################################

data "aws_vpc" "default" {
  default = true
}

# ✅ Use PUBLIC subnets only (so task can get a public IPv4)
data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }

  filter {
    name   = "map-public-ip-on-launch"
    values = ["true"]
  }
}

################################
# Security Group - REUSE EXISTING
################################
data "aws_security_group" "ecs" {
  filter {
    name   = "group-name"
    values = ["${var.project_name}-sg"]
  }

  vpc_id = data.aws_vpc.default.id
}

################################
# ECS Cluster - REUSE EXISTING CLUSTER
################################
data "aws_ecs_cluster" "existing" {
  cluster_name = local.cluster_name
}

################################
# ECS Task Execution Role - REUSE EXISTING ROLE
################################
data "aws_iam_role" "ecs_task_execution" {
  name = "${var.project_name}-task-execution"
}

################################
# ECS Task Definition
################################
resource "aws_ecs_task_definition" "app" {
  family                   = var.project_name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = data.aws_iam_role.ecs_task_execution.arn

  container_definitions = jsonencode([
    {
      name      = "app",
      image     = var.container_image,
      essential = true,

      portMappings = [{
        containerPort = var.container_port,
        hostPort      = var.container_port
      }],

      logConfiguration = {
        logDriver = "awslogs",
        options = {
          awslogs-group         = data.aws_cloudwatch_log_group.app.name
          awslogs-region        = "eu-north-1"
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}

################################
# ECS Service (IMPORT REQUIRED if it already exists)
################################
resource "aws_ecs_service" "app" {
  name            = var.project_name
  cluster         = data.aws_ecs_cluster.existing.arn
  task_definition = aws_ecs_task_definition.app.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200

  network_configuration {
    subnets          = data.aws_subnets.public.ids
    security_groups  = [data.aws_security_group.ecs.id]
    assign_public_ip = true
  }

  lifecycle {
    prevent_destroy = true
  }
}

################################
# Outputs
################################
output "github_role_arn" {
  value = data.aws_iam_role.github_action.arn
}

output "ecr_repo_url" {
  value = data.aws_ecr_repository.app.repository_url
}

output "ecs_cluster_name" {
  value = data.aws_ecs_cluster.existing.cluster_name
}

output "vpc_id_used" {
  value = data.aws_vpc.default.id
}

output "public_subnet_ids_used" {
  value = data.aws_subnets.public.ids
}
