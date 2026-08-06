# ============================================
#  VARIABLES
# ============================================
# Database : 
variable "app_db_username" {
  type      = string
  sensitive = true
  default   = "anne"
}
variable "app_db_name" {
  type    = string
  default = "autopremuim"
}
variable "db" {
  type = object({
    engine         = string
    engine_version = string
  })
  default = {
    engine         = "postgres"
    engine_version = "15"
  }
}

# Application
variable "application_port" {
  type        = number
  default     = 3000
  description = "the port on which the application is running on"
}
variable "supabase_url" {
  type      = string
  sensitive = true
}
variable "supabase_anon_key" {
  type      = string
  sensitive = true
}

variable "internet_port" {
  type        = number
  default     = 80
  description = "the port for the incoming tcp traffic, 80/443"
}

variable "lb_target_type" {
  type        = string
  default     = "instance"
  description = "The target type of the Load Balancer target group (instance or ip)"
}

# ============================================
#  OUTPUTS
# ============================================
output "instance_sg" {
  type  = string
  value = aws_security_group.instnace_security.id
}
output "application_port" {
  value = var.application_port
}
output "lb_hostname" {
  type        = string
  value       = aws_lb.load_balancer.dns_name
  description = "the load balancer dns name"
}
output "lb_target_group_arn" {
  type  = string
  value = aws_lb_target_group.instance_group.arn
}

output "bucket_id" {
  value = aws_s3_bucket.app_bucket.id
}

output "db_secret_id" {
  value = aws_secretsmanager_secret.db_secrets.id
}
output "db_master_secret" {
  value = aws_db_instance.database.master_user_secret[0].secret_arn
}
output "github_actions_role" {
  type        = string
  value       = module.github_actions_role.name
  description = "Github Actions Role name"
}
output "github_actions_role_arn" {
  value = module.github_actions_role.arn
}

output "pulic_subnets" {
  type  = list(string)
  value = module.vpc.public_subnets
}

output "private_subnets" {
  type  = list(string)
  value = module.vpc.private_subnets
}

output "vpc_id" {
  type  = string
  value = module.vpc.vpc_id
}

output "lb_security_sg_id" {
  type  = string
  value = aws_security_group.lb_security.id
}

output "secrets_ssm_policy_arn" {
  type  = string
  value = aws_iam_policy.secrets_ssm_policy.arn
}

output "s3_policy_arn" {
  type  = string
  value = aws_iam_policy.s3_policy.arn
}
