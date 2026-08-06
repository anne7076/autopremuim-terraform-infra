terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
  backend "s3" {
    bucket       = "terraform-state-bucket-f8080b23866255cb548f14e56b"
    key          = "learning/ec2-autoscaling/terraform.tfstate"
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

data "aws_availability_zones" "zones" {
  state = "available"
}
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
data "aws_ami" "amazon_linux" {
  most_recent = true
  # L'ID du compte officiel AWS
  owners = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

module "common_config" {
  source            = "../../shared_config"
  supabase_url      = var.supabase_url
  supabase_anon_key = var.supabase_anon_key
}
resource "aws_iam_instance_profile" "profile" {
  name_prefix = "ec2-iam-profile-"
  role        = aws_iam_role.instance_role.name
}
resource "aws_launch_template" "instance_template" {
  name_prefix   = "autopremuim-template-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.machine_type

  user_data = base64encode(templatefile("${path.module}/run-docker.sh", {
    aws_region       = data.aws_region.current.region
    aws_account_id   = data.aws_caller_identity.current.account_id
    aws_secret_id    = module.common_config.db_secret_id
    master_secret_id = module.common_config.db_master_secret
    image_name       = "autopremuim"
    application_port = module.common_config.application_port
    # s3_bucket_name   = module.common_config.bucket_id
  }))
  vpc_security_group_ids = [module.common_config.instance_sg]

  iam_instance_profile {
    name = aws_iam_instance_profile.profile.name
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "instance_asg" {
  name_prefix = "autopremuim-instance-asg-"
  min_size    = 1
  max_size    = 3
  #   desired_capacity = 1 # remove this when using aws_autoscaling_policy
  vpc_zone_identifier       = module.common_config.pulic_subnets
  health_check_type         = "ELB"
  health_check_grace_period = 300

  launch_template {
    id      = aws_launch_template.instance_template.id
    version = "$Latest"
  }
  lifecycle {
    create_before_destroy = true
  }
  tag {
    key                 = "Name"
    value               = "autopremuim-asg-instance"
    propagate_at_launch = true
  }
}
resource "aws_autoscaling_policy" "asg_policy" {
  name                   = "autopremuim-asg-policy"
  policy_type            = "TargetTrackingScaling"
  autoscaling_group_name = aws_autoscaling_group.instance_asg.name
  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 80.0
  }
  estimated_instance_warmup = 300

}
resource "aws_autoscaling_attachment" "asg_attachment" {
  autoscaling_group_name = aws_autoscaling_group.instance_asg.name
  lb_target_group_arn    = module.common_config.lb_target_group_arn
}

# GITGUN <-> SSM and ASG Config
data "aws_iam_policy_document" "github_actions_ssm" {
  # Allow Ec2 Acces
  statement {
    effect    = "Allow"
    actions   = ["ec2:DescribeInstances"]
    resources = ["*"]
  }

  # Allow Interact with ASG
  statement {
    effect = "Allow"
    actions = [
      "autoscaling:StartInstanceRefresh",
      "autoscaling:DescribeInstanceRefreshes"
    ]
    resources = [aws_autoscaling_group.instance_asg.arn]
  }

  # Allow to send commands
  statement {
    effect = "Allow"
    actions = [
      "ssm:SendCommand"
    ]
    resources = flatten([
      "arn:aws:ec2:${data.aws_region.current.region}:*:instance/*",
      "arn:aws:ssm:${data.aws_region.current.region}::document/AWS-RunShellScript"
    ])
  }

  # Allow to verify the command's state
  statement {
    effect = "Allow"
    actions = [
      "ssm:GetCommandInvocation"
    ]
    resources = [
      "*"
    ]
  }
}
resource "aws_iam_role_policy" "gh_actions_policy_attachment" {
  name_prefix = "github-actions-ssm-policy-"
  role        = module.common_config.github_actions_role
  policy      = data.aws_iam_policy_document.github_actions_ssm.json
}


# ============================================
#  Variables
# ============================================
variable "machine_type" {
  type    = string
  default = "t3.micro"
}
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
output "asg_name" {
  value = aws_autoscaling_group.instance_asg.name
}
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
