########################################
# Data
########################################
data "aws_availability_zones" "available" {}

########################################
# VPC (public only)
########################################
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.project_name}-vpc"
  cidr = "10.0.0.0/16"

  azs            = slice(data.aws_availability_zones.available.names, 0, 2)
  public_subnets = ["10.0.1.0/24", "10.0.2.0/24"]

  enable_nat_gateway = false
  single_nat_gateway = false
  enable_vpn_gateway = false

  tags = {
    Project = var.project_name
  }
}

########################################
# ECR
########################################
resource "aws_ecr_repository" "app" {
  name                 = "${var.project_name}-repo"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Project = var.project_name
  }
}

########################################
# ECS Cluster (public ECS module)
########################################
module "ecs" {
  source  = "terraform-aws-modules/ecs/aws"
  version = "~> 5.0"

  cluster_name = "${var.project_name}-cluster"

  tags = {
    Project = var.project_name
  }
}

########################################
# CloudWatch Logs
########################################
resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.project_name}"
  retention_in_days = 7
  tags = {
    Project = var.project_name
  }
}

########################################
# IAM: Task Execution Role
########################################
resource "aws_iam_role" "task_execution" {
  name = "${var.project_name}-ecsTaskExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "ecs-tasks.amazonaws.com" },
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Project = var.project_name
  }
}

resource "aws_iam_role_policy_attachment" "task_exec_policy" {
  role      = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

########################################
# Security Groups
########################################

# ALB SG (only when enable_alb = true)
resource "aws_security_group" "alb_sg" {
  count       = var.enable_alb ? 1 : 0
  name        = "${var.project_name}-alb-sg"
  description = "ALB public ingress"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "HTTP"
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

  tags = {
    Project = var.project_name
  }
}

# ECS tasks SG
resource "aws_security_group" "ecs_tasks_sg" {
  name        = "${var.project_name}-ecs-tasks-sg"
  description = "ECS tasks security group"
  vpc_id      = module.vpc.vpc_id

  # If ALB enabled -> only allow traffic from ALB SG to container_port
  dynamic "ingress" {
    for_each = var.enable_alb ? [1] : []
    content {
      description     = "From ALB"
      from_port       = var.container_port
      to_port         = var.container_port
      protocol        = "tcp"
      security_groups = [aws_security_group.alb_sg[0].id]
    }
  }

  # If ALB disabled -> allow public access to container_port (simple assignment mode)
  dynamic "ingress" {
    for_each = var.enable_alb ? [] : [1]
    content {
      description = "Public access (no ALB)"
      from_port   = var.container_port
      to_port     = var.container_port
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Project = var.project_name
  }
}

########################################
# Optional ALB
########################################
module "alb" {
  count   = var.enable_alb ? 1 : 0
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 9.0"

  name               = "${var.project_name}-alb"
  load_balancer_type = "application"
  vpc_id             = module.vpc.vpc_id
  subnets            = module.vpc.public_subnets
  security_groups    = [aws_security_group.alb_sg[0].id]

  # Listener on 80 -> forward to target group
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
      name_prefix      = "tg-"
      protocol         = "HTTP"
      port             = var.container_port
      target_type      = "ip"
      health_check = {
        enabled             = true
        path                = "/"
        healthy_threshold   = 2
        unhealthy_threshold = 2
        interval            = 30
        timeout             = 5
        matcher             = "200-399"
      }
    }
  }

  tags = {
    Project = var.project_name
  }
}

########################################
# ECS Task Definition
########################################
resource "aws_ecs_task_definition" "app" {
  family                   = "${var.project_name}-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(var.task_cpu)
  memory                   = tostring(var.task_memory)
  execution_role_arn       = aws_iam_role.task_execution.arn

  container_definitions = jsonencode([
    {
      name      = "app"
      image     = "${aws_ecr_repository.app.repository_url}:${var.image_tag}"
      essential = true

      portMappings = [
        {
          containerPort = var.container_port
          hostPort      = var.container_port
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "PORT", value = tostring(var.container_port) }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.app.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

  tags = {
    Project = var.project_name
  }
}

########################################
# ECS Service (Fargate)
########################################
resource "aws_ecs_service" "app" {
  name            = "${var.project_name}-service"
  cluster         = module.ecs.cluster_id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = module.vpc.public_subnets
    security_groups  = [aws_security_group.ecs_tasks_sg.id]
    assign_public_ip = var.enable_alb ? false : true
  }

  # Attach to ALB only if enabled
  dynamic "load_balancer" {
    for_each = var.enable_alb ? [1] : []
    content {
      target_group_arn = module.alb[0].target_groups["tg"].arn
      container_name   = "app"
      container_port   = var.container_port
    }
  }

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200

  depends_on = [
    aws_iam_role_policy_attachment.task_exec_policy
  ]

  tags = {
    Project = var.project_name
  }
}
