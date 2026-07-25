# Database :
resource "aws_db_instance" "database" {
  instance_class = "db.t3.micro"
  db_name        = "root_database"
  engine         = var.db.engine
  engine_version = var.db.engine_version

  username                    = "root"
  allocated_storage           = 10
  skip_final_snapshot         = true
  manage_master_user_password = true

  db_subnet_group_name   = module.vpc.database_subnet_group_name
  vpc_security_group_ids = [aws_security_group.db_security.id]
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
resource "aws_vpc_security_group_ingress_rule" "allow_ec2_to_db" {
  description                  = "Allow ec2-rds communication"
  ip_protocol                  = "tcp"
  security_group_id            = aws_security_group.db_security.id
  from_port                    = aws_db_instance.database.port
  to_port                      = aws_db_instance.database.port
  referenced_security_group_id = aws_security_group.ec2_security.id
}
resource "aws_vpc_security_group_ingress_rule" "allow_lambda_to_db" {
  description                  = "Allow lambda rotation function to acces the db"
  ip_protocol                  = "tcp"
  security_group_id            = aws_security_group.db_security.id
  from_port                    = aws_db_instance.database.port
  to_port                      = aws_db_instance.database.port
  referenced_security_group_id = aws_security_group.rotation_function.id
}
