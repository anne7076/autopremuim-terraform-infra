terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
  backend "s3" {
    bucket       = "terraform-state-bucket-f8080b23866255cb548f14e56b"
    key          = "learning/eks-kubernetes/terraform.tfstate"
    use_lockfile = true
    encrypt      = true
    region       = "us-east-1"
  }
}

locals {
  is_localstack = terraform.workspace == "localstack"
}
