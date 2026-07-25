terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
  backend "s3" {
    bucket       = "terraform-state-bucket-f8080b23866255cb548f14e56b"
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
}

# VPC
data "aws_availability_zones" "zones" {
  state = "available"
}

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
      security_group_ids  = [aws_security_group.secretsmanager_endpoint.id]
    }
    s3 = {
      service           = "s3"
      vpc_endpoint_type = "Gateway"
      route_table_ids   = module.vpc.private_route_table_ids
    }
  }
}

data "aws_region" "current" {}

# S3 bucket :
resource "aws_s3_bucket" "app_bucket" {
  bucket_prefix = "terraform-app-bucket-"

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
    Version = "2012-"
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
