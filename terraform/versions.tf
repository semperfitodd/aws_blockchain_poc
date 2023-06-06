provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Owner       = "Todd"
      Provisioner = "Terraform"
    }
  }
}

terraform {
  required_version = ">= 1.4.5"
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}