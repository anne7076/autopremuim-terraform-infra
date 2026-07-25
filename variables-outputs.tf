# ============================================
#  VARIABLES
# ============================================
variable "small_machine_type" {
  type    = string
  default = "t3.micro"
}

# Database : 
variable "app_db_username" {
  type      = string
  sensitive = true
  default   = "anne"
}
variable "app_db_name" {
  type = string
  # default = "value"
}
variable "db" {
  type = object({
    engine         = string
    engine_version = string
  })
  default = {
    engine         = "mysql"
    engine_version = "8.0"
  }
}

# Application
variable "app_replica" {
  type = number
  #   default = 1
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
  value       = aws_db_instance.database.address
  description = "the database dns name"
}
output "db_port" {
  value = aws_db_instance.database.port
}

output "lb_hostname" {
  value       = aws_lb.load_balancer.dns_name
  description = "the load balancer dns name"
}

output "bucket_id" {
  value = aws_s3_bucket.app_bucket.id
}
