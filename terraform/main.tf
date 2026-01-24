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
  type    = string
  default = "ecs-fargate-cicd-terraform"
}

variable "github_repo" {
  description = "GitHub repo in format owner/repo"
  type        = string
  default     = "Zahra-Ismail/ecs-fargate-cicd-terraform"
}

# Passed from GitHub Actions
variable "container_image" {
  description = "Full ECR image URI with tag"
  type        = string
}

variable "container_port" {
  type    = number
  default = 8080
}

################################
# Existing AWS Infrastructure
################################
variable "existing_vpc_id" {
  type    = string
  default = "vpc-01f7999b335c94e65"
}

variable "existing_private_subnet_ids" {
  type = list(string)
  default = [
    "subnet-01e277a197a998399",
    "subnet-046d32a91c65f6d3c"
  ]
}

variable "existing_security_group_id" {
  type    = string
  default = "sg-0afdd074401ffe6ed"
}

variable "existing_ecr_repo_name" {
  type    = string
  default = "ecs-fargate-cicd-terraform"
}

################################
# Data Sources (Existing Resources)
################################
data "aws_vpc" "existing" {
  id = var.existing_vpc_id
}

data "aws_security_group" "ecs" {
  id = var.existing_security_group_id
}

data "aws_ecr_repository" "app" {
  name = var.existing_ecr_repo_name
}

################################
# ECS Cluster
################################
module "ecs" {
  source  = "terraform-aws-modules/ecs/aws"
  version = "5.11.4"

  cluster_name = "${var.project_name}-cluster"
}

################################
# ECS Task Execution Role
################################
resource "aws_iam_role" "ecs_task_execution" {
  name = "${var.project_name}-task-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution_policy" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

################################
# CloudWatch Logs
################################
resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${var.project_name}"
  retention_in_days = 7
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
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn

  container_definitions = jsonencode([
    {
      name      = "app"
      image     = var.container_image
      essential = true

      portMappings = [{
        containerPort = var.container_port
        hostPort      = var.container_port
      }]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs.name
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

  network_configuration {
    subnets          = var.existing_private_subnet_ids
    security_groups  = [data.aws_security_group.ecs.id]
    assign_public_ip = false
  }

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200
}

################################
# Outputs
################################
output "ecr_repo_url" {
  value = data.aws_ecr_repository.app.repository_url
}

output "ecs_cluster_name" {
  value = module.ecs.cluster_name
}
