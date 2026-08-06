terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
  backend "s3" {
    bucket       = "terraform-state-bucket-f8080b23866255cb548f14e56b"
    key          = "learning/ecs-fragate/terraform.tfstate"
    use_lockfile = true
    encrypt      = true
    region       = "us-east-1"
  }

}
locals {
  is_localstack = terraform.workspace == "localstack"
}
provider "aws" {
  profile = local.is_localstack ? "localstack" : "default"
  region  = "us-east-1"
  default_tags {
    tags = {
      "managedBy" = "Terraform"
    }
  }
}
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
module "common_config" {
  source            = "../../shared_config"
  supabase_url      = var.supabase_url
  supabase_anon_key = var.supabase_anon_key
  lb_target_type    = "ip"
}

resource "aws_ecs_cluster" "autopremuim_cluster" {
  name = "autopremuim-cluster"
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}
resource "aws_ecs_cluster_capacity_providers" "fargate_provider" {
  cluster_name       = aws_ecs_cluster.autopremuim_cluster.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]
  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    base              = 1
    weight            = 20
  }
  default_capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    base              = 0
    weight            = 80
  }
}

resource "aws_ecs_task_definition" "autopremuim_task" {
  family                   = "autopremuim-ecs-task"
  task_role_arn            = aws_iam_role.task_role.arn
  execution_role_arn       = aws_iam_role.execution_role.arn
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  network_mode             = "awsvpc"
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }
  container_definitions = jsonencode([{
    name      = "autopremuim",
    image     = "${data.aws_caller_identity.current.id}.dkr.ecr.${data.aws_region.current.region}.amazonaws.com/autopremuim:latest"
    essential = true
    portMappings = [
      {
        containerPort = 3000
        hostPort      = 3000
      }
    ]
    environment = [
      { name  = "AWS_SECRET_ID",
        value = "${module.common_config.db_secret_id}"
      },
      {
        name  = "AWS_REGION",
        value = "${data.aws_region.current.region}"
      }
    ]
    secrets = [
      {
        name      = "SUPABASE_URL"
        valueFrom = "arn:aws:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.id}:parameter/app/supabase/url"
      },
      {
        name      = "SUPABASE_PUBLISHABLE_KEY"
        valueFrom = "arn:aws:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.id}:parameter/app/supabase/anon_key"
      },
      {
        name      = "APP_URL"
        valueFrom = "arn:aws:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.id}:parameter/app/public_url"
      },
      {
        name      = "S3_BUCKET_NAME"
        valueFrom = "arn:aws:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.id}:parameter/app/bucket_name"
      }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.ecs_logs.name
        "awslogs-region"        = data.aws_region.current.region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}
resource "aws_ecs_service" "autopremuim_service" {
  name            = "autopremuim-service"
  cluster         = aws_ecs_cluster.autopremuim_cluster.name
  task_definition = aws_ecs_task_definition.autopremuim_task.arn
  desired_count   = 3

  availability_zone_rebalancing      = "ENABLED"
  health_check_grace_period_seconds  = 300
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  force_new_deployment               = true

  network_configuration {
    assign_public_ip = false
    subnets          = module.common_config.private_subnets
    security_groups  = [module.common_config.instance_sg]
  }

  load_balancer {
    target_group_arn = module.common_config.lb_target_group_arn
    container_name   = "autopremuim"
    container_port   = 3000
  }

  lifecycle {
    # prevent terraform to revert external change
    ignore_changes = [
      desired_count,
      task_definition,
      capacity_provider_strategy
    ]
  }
}

resource "aws_cloudwatch_log_group" "ecs_logs" {
  name              = "/ecs/autopremuim"
  retention_in_days = 7
}

resource "aws_appautoscaling_target" "name" {
  max_capacity       = 5
  min_capacity       = 2
  resource_id        = "service/${aws_ecs_cluster.autopremuim_cluster.name}/${aws_ecs_service.autopremuim_service.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}
resource "aws_appautoscaling_policy" "name" {
  name               = "autopremuim-cpu-scaling"
  resource_id        = aws_appautoscaling_target.name.resource_id
  scalable_dimension = aws_appautoscaling_target.name.scalable_dimension
  service_namespace  = aws_appautoscaling_target.name.service_namespace
  policy_type        = "TargetTrackingScaling"

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value = 70.0
  }
}

# ============================================
#  ROLES & POLICIES
# ============================================
resource "aws_iam_role" "task_role" {
  name_prefix = "ecs-task-role-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}
resource "aws_iam_role_policy_attachment" "allow_s3" {
  policy_arn = module.common_config.s3_policy_arn
  role       = aws_iam_role.task_role.name
}
resource "aws_iam_role_policy_attachment" "task_secretsmanager" {
  policy_arn = module.common_config.secrets_ssm_policy_arn
  role       = aws_iam_role.task_role.name
}

resource "aws_iam_role" "execution_role" {
  name_prefix = "ecs-execution-role-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}
resource "aws_iam_role_policy_attachment" "allow_ecr_logs" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
  role       = aws_iam_role.execution_role.name
}
resource "aws_iam_role_policy_attachment" "allow_secretsmanager" {
  policy_arn = module.common_config.secrets_ssm_policy_arn
  role       = aws_iam_role.execution_role.name
}

# ============================================
#  VARIABLES
# ============================================
variable "supabase_url" {
  type      = string
  sensitive = true
}
variable "supabase_anon_key" {
  type      = string
  sensitive = true
}

# ============================================
#  OUTPUTS
# ============================================
output "lb_hostname" {
  type        = string
  value       = module.common_config.lb_hostname
  description = "the load balancer dns name"
}
output "github_actions_role_arn" {
  type  = string
  value = module.common_config.github_actions_role_arn
}
output "bucket" {
  value = module.common_config.bucket_id
}
