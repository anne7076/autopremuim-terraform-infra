# ============================================
#  VARIABLES
# ============================================
variable "small_machine_type" {
  type    = string
  default = "t3.micro"
  #   validation {
  #     condition     = var.small_machine_type in ["t2.micro", "t3.micro"]
  #     error_message = "accepted machine type are ...."
  #   }
}
variable "big_machine_type" {
  type    = string
  default = "...."
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

# ============================================
#  OUTPUTS
# ============================================
output "db_ip_adress" {
  value = aws_db_instance.mysql_database.address
}
