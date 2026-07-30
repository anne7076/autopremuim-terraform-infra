# ============================================
#  Secrets Manager and Rotation Configuration
# ============================================
resource "aws_secretsmanager_secret" "db_secrets" {
  name_prefix             = "app/database/credentials-"
  description             = "the app secrets for database, app shouldn't use master secrets"
  recovery_window_in_days = 0
}
resource "aws_secretsmanager_secret_version" "db_secrets" {
  secret_id = aws_secretsmanager_secret.db_secrets.id

  secret_string = jsonencode({
    engine    = "postgres"
    host      = aws_db_instance.database.address
    port      = aws_db_instance.database.port
    username  = var.app_db_username
    password  = "change-this-immediately"
    dbname    = var.app_db_name
    masterarn = aws_db_instance.database.master_user_secret[0].secret_arn
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}
resource "aws_secretsmanager_secret_rotation" "db_password" {
  secret_id           = aws_secretsmanager_secret.db_secrets.id
  rotation_lambda_arn = aws_serverlessapplicationrepository_cloudformation_stack.rotation_function.outputs["RotationLambdaARN"]
  rotate_immediately  = true

  rotation_rules {
    automatically_after_days = 30
    duration                 = "2h" # TODO: is this too long ?
  }
}

resource "aws_serverlessapplicationrepository_cloudformation_stack" "rotation_function" {
  name           = "SecretsManager-PostgreSQLRotation-MultiUser"
  application_id = "arn:aws:serverlessrepo:us-east-1:297356227824:applications/SecretsManagerRDSPostgreSQLRotationMultiUser"
  capabilities   = ["CAPABILITY_IAM", "CAPABILITY_RESOURCE_POLICY"]

  parameters = {
    functionName        = "SecretsManagerRDSPostgreSQLRotationMultiUser"
    endpoint            = "https://secretsmanager.${data.aws_region.current.region}.amazonaws.com"
    vpcSubnetIds        = join(",", module.vpc.private_subnets)
    vpcSecurityGroupIds = aws_security_group.rotation_function.id
    # PARAMÈTRE SUPPLÉMENTAIRE REQUIS EN MULTI-USER :
    masterSecretArn       = aws_db_instance.database.master_user_secret[0].secret_arn
    masterSecretKmsKeyArn = aws_db_instance.database.master_user_secret[0].kms_key_id
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

# =========================================================================
#  SSM PARAMETER STORE (Application settings decoupling)
# =========================================================================

resource "aws_ssm_parameter" "supabase_url" {
  name        = "/app/supabase/url"
  description = "The Supabase API endpoint URL for Auth client"
  type        = "String"
  value       = var.supabase_url
}

resource "aws_ssm_parameter" "supabase_anon_key" {
  name        = "/app/supabase/anon_key"
  description = "The Supabase anonymous API key for Auth client"
  type        = "SecureString"
  value       = var.supabase_anon_key
}

resource "aws_ssm_parameter" "app_url" {
  name        = "/app/public_url"
  description = "The application public domain URL"
  type        = "String"
  value       = "http://${aws_lb.load_balancer.dns_name}"
}

resource "aws_ssm_parameter" "s3_bucket_name" {
  name        = "/app/bucket_name"
  description = "The bucket that the app uses"
  type        = "String"
  value       = aws_s3_bucket.app_bucket.bucket
}
