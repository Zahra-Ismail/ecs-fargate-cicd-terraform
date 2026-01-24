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

variable "container_image" {
  description = "Full ECR image URI with tag"
  type        = string
}

variable "container_port" {
  type    = number
  default = 8080
}

variable "existing_vpc_id" {
  description = "Existing VPC ID"
  type        = string
  default     = "vpc-01f7999b335c94e65"
}

# ✅ Use PUBLIC subnets when you want public IP on tasks
variable "existing_public_subnet_ids" {
  description = "Existing public subnet IDs (2 subnets in 2 AZs)"
  type        = list(string)
  default     = [
    "subnet-0164f734957437b65",
    "subnet-06ea0eeeb4128fb22"
  ]
}

variable "existing_security_group_id" {
  description = "Existing security group ID for ECS tasks"
  type        = string
  default     = "sg-0afdd074401ffe6ed"
}

variable "existing_ecr_repo_name" {
  description = "Existing ECR repository name"
  type        = string
  default     = "ecs-fargate-cicd-terraform"
}

################################
# Use EXISTING VPC / SG / Subnets / ECR (DATA SOURCES)
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

data "aws_subnet" "public" {
  for_each = toset(var.existing_public_subnet_ids)
  id       = each.value
}

################################
# ECS Cluster (module)
################################
module "ecs" {
  source  = "terraform-aws-modules/ecs/aws"
  version = "5.11.4"

  cluster_name                = "${var.project_name}-cluster"
  create_cloudwatch_log_group = false
}

################################
# Use EXISTING ECS Task Execution Role (already exists)
################################
data "aws_iam_role" "ecs_task_execution" {
  name = "${var.project_name}-task-execution"
}

################################
# Use EXISTING CloudWatch Log Group (already exists)
################################
data "aws_cloudwatch_log_group" "ecs" {
  name = "/ecs/${var.project_name}"
}

################################
# ECS Task Definition (create/update)
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
          awslogs-group         = data.aws_cloudwatch_log_group.ecs.name
          awslogs-region        = "eu-north-1"
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
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

output "public_subnet_ids_used" {
  value = var.existing_public_subnet_ids
}
