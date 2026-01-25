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
}

################################
# Existing resources (REUSE)
################################

# Reuse the existing ECR repo instead of creating it again
data "aws_ecr_repository" "app" {
  name = var.project_name
}

# Reuse the existing GitHub OIDC provider instead of creating it again
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

# Reuse the existing CloudWatch log group instead of creating it again
data "aws_cloudwatch_log_group" "app" {
  name = local.app_log_group
}

################################
# IAM Role for GitHub Actions (OIDC) - REUSE EXISTING ROLE
################################

# Your role already exists: arn:aws:iam::395512255485:role/Github_Action
# So do NOT create it again.
data "aws_iam_role" "github_action" {
  name = "Github_Action"
}

# (Optional but recommended)
# Terraform CAN attach the policy to an existing role.
resource "aws_iam_role_policy_attachment" "github_admin" {
  role       = data.aws_iam_role.github_action.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

################################
# VPC - USE DEFAULT VPC (fixes VpcLimitExceeded)
################################

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

################################
# Security Group (in default VPC)
################################
resource "aws_security_group" "ecs" {
  name   = "${var.project_name}-sg"
  vpc_id = data.aws_vpc.default.id

  ingress {
    from_port   = var.container_port
    to_port     = var.container_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

################################
# ECS Cluster
################################
module "ecs" {
  source  = "terraform-aws-modules/ecs/aws"
  version = "5.11.4"

  cluster_name = "${var.project_name}-cluster"

  # Prevent the module from trying to create a cluster log group that already exists
  create_cloudwatch_log_group = false
}

################################
# ECS Task Execution Role - REUSE EXISTING ROLE
################################

# This role already exists in your account, so do NOT create it again.
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
# ECS Service
################################
resource "aws_ecs_service" "app" {
  name            = var.project_name
  cluster         = module.ecs.cluster_id
  task_definition = aws_ecs_task_definition.app.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = true
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
  value = module.ecs.cluster_name
}

output "vpc_id_used" {
  value = data.aws_vpc.default.id
}
