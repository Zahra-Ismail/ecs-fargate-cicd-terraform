terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }

  backend "s3" {
    bucket         = var.tf_state_bucket
    key            = "ecs-fargate-demo/terraform.tfstate"
    region         = var.aws_region
    dynamodb_table = var.tf_lock_table
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
}

########################
# VARIABLES
########################
variable "aws_region" { type = string }
variable "project"    { type = string }

variable "tf_state_bucket" { type = string }
variable "tf_lock_table"   { type = string }

variable "ecr_repo_name" { type = string }

########################
# OUTPUTS
########################
output "ecr_repo_url" {
  value = aws_ecr_repository.app.repository_url
}

output "alb_dns_name" {
  value = module.alb.lb_dns_name
}

########################
# VPC (public + private)
########################
data "aws_availability_zones" "available" {}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.project}-vpc"
  cidr = "10.0.0.0/16"

  azs             = slice(data.aws_availability_zones.available.names, 0, 2)
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true

  tags = { Project = var.project }
}

########################
# ECR
########################
resource "aws_ecr_repository" "app" {
  name                 = var.ecr_repo_name
  image_tag_mutability = "MUTABLE"
}

resource "aws_ecr_lifecycle_policy" "keep_last_20" {
  repository = aws_ecr_repository.app.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 20 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 20
      }
      action = { type = "expire" }
    }]
  })
}

########################
# ALB + Security Groups
########################
resource "aws_security_group" "alb_sg" {
  name   = "${var.project}-alb-sg"
  vpc_id = module.vpc.vpc_id

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
}

resource "aws_security_group" "ecs_sg" {
  name   = "${var.project}-ecs-sg"
  vpc_id = module.vpc.vpc_id

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 9.0"

  name                       = "${var.project}-alb"
  vpc_id                     = module.vpc.vpc_id
  subnets                    = module.vpc.public_subnets
  security_groups            = [aws_security_group.alb_sg.id]
  enable_deletion_protection = false

  listeners = {
    http = {
      port     = 80
      protocol = "HTTP"
      forward = {
        target_group_key = "tg"
      }
    }
  }

  target_groups = {
    tg = {
      name_prefix = "tg-"
      protocol    = "HTTP"
      port        = 8080
      target_type = "ip"

      health_check = {
        path                = "/health"
        matcher             = "200"
        interval            = 30
        timeout             = 5
        healthy_threshold   = 2
        unhealthy_threshold = 2
      }
    }
  }
}

########################
# ECS Fargate (public ECS module)
########################
resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.project}"
  retention_in_days = 7
}

module "ecs" {
  source  = "terraform-aws-modules/ecs/aws"
  version = "~> 5.0"

  cluster_name = var.project

  fargate_capacity_providers = {
    FARGATE = {
      default_capacity_provider_strategy = {
        weight = 1
      }
    }
  }

  services = {
    app = {
      cpu    = 256
      memory = 512

      desired_count = 1
      launch_type   = "FARGATE"

      subnet_ids         = module.vpc.private_subnets
      security_group_ids = [aws_security_group.ecs_sg.id]

      assign_public_ip = false

      load_balancer = {
        service = {
          target_group_arn = module.alb.target_groups["tg"].arn
          container_name   = "app"
          container_port   = 8080
        }
      }

      container_definitions = {
        app = {
          name  = "app"
          image = "${aws_ecr_repository.app.repository_url}:latest"

          port_mappings = [
            { containerPort = 8080, protocol = "tcp" }
          ]

          essential = true

          log_configuration = {
            logDriver = "awslogs"
            options = {
              awslogs-group         = aws_cloudwatch_log_group.app.name
              awslogs-region        = var.aws_region
              awslogs-stream-prefix = "app"
            }
          }

          health_check = {
            command     = ["CMD-SHELL", "curl -f http://localhost:8080/health || exit 1"]
            interval    = 30
            timeout     = 5
            retries     = 3
            startPeriod = 20
          }
        }
      }
    }
  }

  tags = { Project = var.project }
}
