terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

provider "aws" {
  profile = "default"
  region  = "us-east-1"
}

# VPC
data "aws_availability_zones" "zones" {
  state = "available"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.6.0"

  name                    = "local"
  cidr                    = "10.0.0.0/16"
  azs                     = data.aws_availability_zones.zones.names
  public_subnets          = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets         = ["10.0.10.0/24", "10.0.20.0/24"]
  enable_dns_hostnames    = true
  enable_dns_support      = true
  map_public_ip_on_launch = true
}

# S3 bucket :
resource "aws_s3_bucket" "terraform_bucket" {
  bucket_prefix = "terraform-bucket-"
  #   bucket_namespace = "global"

  tags = {
    Name = "terraform_bucket"
  }
}

# Database :
resource "aws_db_instance" "mysql_database" {
  instance_class = "db.t3.micro"
  db_name        = "terraform_database"
  engine         = "mysql"
  engine_version = "8.0"

  username            = var.database_username
  password            = var.database_password
  allocated_storage   = 10
  skip_final_snapshot = true

  db_subnet_group_name   = aws_db_subnet_group.db_subnets.name
  vpc_security_group_ids = [aws_security_group.db_security.id]
}
resource "aws_db_subnet_group" "db_subnets" {
  name       = "db_subnet_group"
  subnet_ids = module.vpc.private_subnets

}
resource "aws_security_group" "db_security" {
  name_prefix = "db_security_"
  vpc_id      = module.vpc.vpc_id
  egress {
    cidr_blocks = ["0.0.0.0/0"]
    description = "allow all"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
  }
  lifecycle {
    create_before_destroy = true
  }
}
resource "aws_vpc_security_group_ingress_rule" "db_security_rule" {
  ip_protocol                  = "tcp"
  security_group_id            = aws_security_group.db_security.id
  from_port                    = aws_db_instance.mysql_database.port
  to_port                      = aws_db_instance.mysql_database.port
  referenced_security_group_id = aws_security_group.ec2_security.id
}

# EC2 Instance :
data "aws_ami" "amazon_linux" {
  most_recent = true
  # L'ID du compte officiel AWS
  owners = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

resource "aws_instance" "ec2_instance" {
  #   for_each               = module.vpc.public_subnets
  count                  = 2
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.small_machine_type
  subnet_id              = module.vpc.public_subnets[0]
  vpc_security_group_ids = [aws_security_group.ec2_security.id]

  user_data = templatefile("${path.module}/code.sh", {
    db_host     = aws_db_instance.mysql_database.address
    db_user     = aws_db_instance.mysql_database.username
    db_password = aws_db_instance.mysql_database.password
    db_name     = aws_db_instance.mysql_database.db_name
  })
  user_data_replace_on_change = true
  tags = {
    Name = "ec2_instance_${count.index}"
  }
}

resource "aws_security_group" "ec2_security" {
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

resource "aws_vpc_security_group_ingress_rule" "ec2_security_rule" {
  security_group_id            = aws_security_group.ec2_security.id
  ip_protocol                  = "tcp"
  from_port                    = var.application_port
  to_port                      = var.application_port
  referenced_security_group_id = aws_security_group.lb_security.id
}

# Load Balancer :
resource "aws_lb" "load_balancer" {
  name               = "test-lb"
  load_balancer_type = "application"
  subnets            = module.vpc.public_subnets
  security_groups    = [aws_security_group.lb_security.id]
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

resource "aws_vpc_security_group_ingress_rule" "lb_security_rule" {
  security_group_id = aws_security_group.lb_security.id
  ip_protocol       = "tcp"
  from_port         = var.internet_port
  to_port           = var.internet_port
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_lb_listener" "lb_listener" {
  # le port d'ecoute public
  load_balancer_arn = aws_lb.load_balancer.arn
  protocol          = "HTTP"
  port              = var.internet_port
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ec2_group.arn
  }
}

resource "aws_lb_target_group" "ec2_group" {
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

resource "aws_lb_target_group_attachment" "lb_attachement" {
  count            = 2
  target_group_arn = aws_lb_target_group.ec2_group.arn
  target_id        = aws_instance.ec2_instance[count.index].id
  port             = var.application_port
}

