terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

provider "aws" {
  profile = "localstack"
  region  = "us-east-1"
}

# network :
resource "aws_vpc" "local_vpc" {
  cidr_block = "172.16.0.0/16"
  tags = {
    Name = "local_vpc"
  }
}

resource "aws_subnet" "public_subnet" {
  vpc_id     = aws_vpc.local_vpc.id
  cidr_block = "172.16.1.0/24"

  tags = {
    Name = "public_subnet"
  }
}

resource "aws_subnet" "db_subnet" {
  for_each   = toset([1, 2])
  vpc_id     = aws_vpc.local_vpc.id
  cidr_block = "172.16.10.0/24"

  tags = {
    "name" = "private_subnet_${each.value}"
  }
}

# S3 bucket :
resource "aws_s3_bucket" "terraform_bucket" {
  bucket           = "test"
  bucket_namespace = "global"

  tags = {
    Name = "terraform_bucket"
  }
}

# Database :
resource "aws_db_instance" "mysql_database" {
  instance_class      = "db.t3.micro"
  db_name             = "database"
  engine              = "mysql"
  engine_version      = "8.0"
  username            = var.database_username
  password            = var.database_username
  allocated_storage   = 10
  skip_final_snapshot = true
  #   db_subnet_group_name = aws_db_subnet_group.db_subnet.name
}

resource "aws_db_subnet_group" "db_subnet" {
  subnet_ids = [aws_subnet.db_subnet.id]
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
  count           = 2
  ami             = data.aws_ami.amazon_linux.id
  instance_type   = var.small_machine_type
  subnet_id       = aws_subnet.public_subnet.id
  security_groups = [aws_security_group.public_access.name]
  cpu_options {
    core_count       = 2
    threads_per_core = 2
  }
  tags = {
    Name = "ec2_instance_${count.index}"
  }
}

resource "aws_security_group" "public_access" {
  name = "public_access"
}

resource "aws_security_group_rule" "allow_http" {
  type              = "ingress"
  security_group_id = aws_security_group.public_access.id
  protocol          = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_blocks       = ["0.0.0.0/0"]
}

# Load Balancer :
resource "aws_lb" "load_balancer" {
  load_balancer_type = "application"
  subnets            = [aws_subnet.public_subnet.id]
}

resource "aws_lb_listener" "lb_listener" {
  load_balancer_arn = aws_lb.load_balancer.arn
  protocol          = "HTTP"
  port              = 80
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ec2_group.arn
  }
}

resource "aws_lb_target_group" "ec2_group" {
  port     = 80
  protocol = "HTTP"
  health_check {
    path     = "/health"
    interval = 5
    timeout  = 10

  }
}

resource "aws_lb_target_group_attachment" "lb_attachement" {
  for_each         = aws_instance.ec2_instance
  target_group_arn = aws_lb_target_group.ec2_group.arn
  target_id        = each.value.id
  port             = 80
}
