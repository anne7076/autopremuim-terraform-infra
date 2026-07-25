# EC2 Instance :
resource "aws_instance" "ec2_instance" {
  count                  = var.app_replica
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.small_machine_type
  subnet_id              = module.vpc.private_subnets[count.index % length(module.vpc.private_subnets)]
  vpc_security_group_ids = [aws_security_group.ec2_security.id]

  #TODO: remove this test and deploy a real project
  user_data                   = templatefile("${path.module}/run-docker.sh", {})
  user_data_replace_on_change = true
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name
  tags = {
    Name = "ec2_instance_${count.index}"
  }
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  # L'ID du compte officiel AWS
  owners = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
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
resource "aws_vpc_security_group_ingress_rule" "allow_lb_to_ec2" {
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

resource "aws_vpc_security_group_ingress_rule" "allow_public_to_lb" {
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
  count            = var.app_replica
  target_group_arn = aws_lb_target_group.ec2_group.arn
  target_id        = aws_instance.ec2_instance[count.index].id
  port             = var.application_port
}
