data "aws_secretsmanager_random_password" "db_password" {
  password_length     = 12
  exclude_punctuation = false
  include_space       = false
  exclude_characters  = "\"'@/\\"
}

resource "aws_secretsmanager_secret" "db_secrets" {
  name_prefix             = "app/database/credentials-"
  description             = "the app secrets for database, app shouldn't use master secrets"
  recovery_window_in_days = 0
}
resource "aws_secretsmanager_secret_version" "db_secrets" {
  secret_id = aws_secretsmanager_secret.db_secrets.id

  secret_string = jsonencode({
    engine   = "mysql"
    host     = aws_db_instance.database.address
    port     = aws_db_instance.database.port
    username = var.app_db_username
    password = data.aws_secretsmanager_random_password.db_password.random_password
    dbname   = var.app_db_name
  })
}
resource "aws_secretsmanager_secret_rotation" "db_password" {
  secret_id           = data.aws_secretsmanager_random_password.db_password.id
  rotation_lambda_arn = aws_serverlessapplicationrepository_cloudformation_stack.rotation_function.outputs["RotationLambdaARN"]
  rotate_immediately  = true

  rotation_rules {
    automatically_after_days = 30
    duration                 = "2h" # TODO: is this too long ?
  }
}

resource "aws_serverlessapplicationrepository_cloudformation_stack" "rotation_function" {
  name           = "SecretsManager-MySQLRotation-MultiUser"
  application_id = "arn:aws:serverlessrepo:us-east-1:297356227824:applications/SecretsManagerRDSMySQLRotationMultiUser"
  capabilities   = ["CAPABILITY_IAM", "CAPABILITY_RESOURCE_POLICY"]

  parameters = {
    functionName        = "SecretsManagerRDSMySQLRotationMultiUser"
    endpoint            = "https://secretsmanager.${data.aws_region.current.region}.amazonaws.com"
    vpcSubnetIds        = join(",", module.vpc.private_subnets)
    vpcSecurityGroupIds = aws_security_group.rotation_function.id
    # PARAMÈTRE SUPPLÉMENTAIRE REQUIS EN MULTI-USER :
    masterSecretArn = aws_db_instance.database.master_user_secret[0].secret_arn
  }
}

resource "aws_security_group" "rotation_function" {
  name_prefix = "rotation-function-"
  vpc_id      = module.vpc.vpc_id

  egress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
  }
}

resource "aws_security_group" "secretsmanager_endpoint" {
  name_prefix = "secretsmanager_endpoint_"
  vpc_id      = module.vpc.vpc_id
}
# Règle autorisant le trafic HTTPS (443) provenant du SG de la Lambda
resource "aws_vpc_security_group_ingress_rule" "allow_lambda_to_endpoint" {
  security_group_id            = aws_security_group.secretsmanager_endpoint.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.rotation_function.id
}
