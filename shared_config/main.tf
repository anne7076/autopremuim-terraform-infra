data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
data "aws_availability_zones" "zones" {
  state = "available"
}

# ============================================
#  VPC and Endpoints
# ============================================
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.6.0"

  name                         = "local"
  cidr                         = "10.0.0.0/16"
  azs                          = data.aws_availability_zones.zones.names
  public_subnets               = ["10.0.1.0/24", "10.0.2.0/24"]     # for the Load Balancer
  private_subnets              = ["10.0.101.0/24", "10.0.102.0/24"] # for the ec2 instances
  database_subnets             = ["10.0.201.0/24", "10.0.202.0/24"] # for the database
  create_database_subnet_group = true
  enable_dns_hostnames         = true
  enable_dns_support           = true
  map_public_ip_on_launch      = true # TODO: does the lb need that ?
}

module "vpc_endpoints" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "~> 6.6.0"
  vpc_id  = module.vpc.vpc_id
  #   security_group_ids = module.vpc.default_security_group_id # TODO : do i need that ?

  endpoints = {
    secretsmanager = {
      service             = "secretsmanager"
      vpc_endpoint_type   = "Interface"
      subnet_ids          = module.vpc.private_subnets
      private_dns_enabled = true
      security_group_ids  = [aws_security_group.vpc_endpoints_sg.id]
    }
    kms = {
      service             = "kms"
      vpc_endpoint_type   = "Interface"
      subnet_ids          = module.vpc.private_subnets
      private_dns_enabled = true
      security_group_ids  = [aws_security_group.vpc_endpoints_sg.id]
    }
    logs = {
      service             = "logs"
      vpc_endpoint_type   = "Interface"
      subnet_ids          = module.vpc.private_subnets
      private_dns_enabled = true
      security_group_ids  = [aws_security_group.vpc_endpoints_sg.id]
    }
  }
}
resource "aws_security_group" "vpc_endpoints_sg" {
  name_prefix = "vpc-endpoints-"
  vpc_id      = module.vpc.vpc_id
}
resource "aws_vpc_security_group_ingress_rule" "allow_access_to_endpoints" {
  security_group_id = aws_security_group.vpc_endpoints_sg.id
  description       = "Allow HTTPS connection from all vpc address"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = module.vpc.vpc_cidr_block
}


# On crée le repository ECR
resource "aws_ecr_repository" "docker_image_repo" {
  name                 = "autopremuim"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
}
# resource "aws_ecr_lifecycle_policy" "ecr_lifecycle" {
#   repository = aws_ecr_repository.docker_image_repo.name
#   policy = jsonencode({
#     rule = [
#       {
#         rulePriority = 1
#         description  = "Keep last 2 tagged images"
#         selection = {
#           tagStatus   = "tagged"
#           countType   = "imageCountMoreThan"
#           countNumber = 2
#         }
#         action = {
#           type = "expire"
#         }
#       },
#     ]
#   })
# }

# ============================================
#  S3 bucket Configuration
# ============================================
resource "aws_s3_bucket" "app_bucket" {
  bucket_prefix = "terraform-app-bucket-"
  force_destroy = true
  tags = {
    Name = "terraform_bucket"
  }
}

resource "aws_s3_bucket_cors_configuration" "bucket_cors" {
  bucket = aws_s3_bucket.app_bucket.id
  cors_rule {
    allowed_methods = ["GET", "PUT", "POST"]
    allowed_origins = ["*"]
    allowed_headers = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}
resource "aws_s3_bucket_public_access_block" "allow_public" {
  bucket                  = aws_s3_bucket.app_bucket.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}
resource "aws_s3_bucket_policy" "allow_public_read" {
  bucket = aws_s3_bucket.app_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Principal = "*"
        Resource  = ["${aws_s3_bucket.app_bucket.arn}/*"]
      }
    ]
  })
}

# ============================================
#  Instance Security Group
# ============================================
resource "aws_security_group" "instnace_security" {
  name_prefix = "ec2_security_"
  vpc_id      = module.vpc.vpc_id

  egress {
    cidr_blocks = ["0.0.0.0/0"]
    description = "allw all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
  }
  lifecycle {
    create_before_destroy = true
  }
}
resource "aws_vpc_security_group_ingress_rule" "allow_lb_to_ec2" {
  security_group_id            = aws_security_group.instnace_security.id
  ip_protocol                  = "tcp"
  from_port                    = var.application_port
  to_port                      = var.application_port
  referenced_security_group_id = aws_security_group.lb_security.id
}

# ============================================
#  Load Balancer : ALB
# ============================================
resource "aws_lb" "load_balancer" {
  name               = "test-lb"
  load_balancer_type = "application"
  subnets            = module.vpc.public_subnets
  security_groups    = [aws_security_group.lb_security.id]
}
resource "aws_lb_listener" "lb_listener" {
  # le port d'ecoute public
  load_balancer_arn = aws_lb.load_balancer.arn
  protocol          = "HTTP"
  port              = var.internet_port
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.instance_group.arn
  }
}
resource "aws_lb_target_group" "instance_group" {
  port     = var.application_port
  protocol = "HTTP"
  vpc_id   = module.vpc.vpc_id
  health_check {
    path                = "/health"
    interval            = 30
    timeout             = 10
    healthy_threshold   = 3
    unhealthy_threshold = 2
  }
}

resource "aws_security_group" "lb_security" {
  name_prefix = "lb_security_"
  vpc_id      = module.vpc.vpc_id
  egress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
  }
  lifecycle {
    create_before_destroy = true
  }
}
resource "aws_vpc_security_group_ingress_rule" "allow_public_to_lb" {
  security_group_id = aws_security_group.lb_security.id
  ip_protocol       = "tcp"
  from_port         = var.internet_port
  to_port           = var.internet_port
  cidr_ipv4         = "0.0.0.0/0"
}
