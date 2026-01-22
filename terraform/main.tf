terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }

  # IMPORTANT: backend cannot use variables.
  # Provide bucket/region/dynamodb_table via `terraform init -backend-config=...`
  backend "s3" {
    key     = "ecs-fargate-demo/terraform.tfstate"
    encrypt = true
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
