# ============================================
#  VARIABLES
# ============================================
variable "small_machine_type" {
  type    = string
  default = "t3.micro"
}
variable "database_username" {
  type      = string
  sensitive = true
  default   = "anne"
}
variable "database_password" {
  type      = string
  sensitive = true
  default   = "changeme"
}
variable "application_port" {
  type        = number
  default     = 5000
  description = "the port on which the application is running on"
}
variable "internet_port" {
  type        = number
  default     = 80
  description = "the port for the incoming tcp traffic, 80/443"
}

# ============================================
#  OUTPUTS
# ============================================
output "db_hostname" {
  value       = aws_db_instance.mysql_database.address
  description = "the database dns name"
}
output "db_port" {
  value = aws_db_instance.mysql_database.port
}

output "lb_hostname" {
  value       = aws_lb.load_balancer.dns_name
  description = "the load balancer dns name"
}

output "bucket_id" {
  value = aws_s3_bucket.terraform_bucket.id
}
