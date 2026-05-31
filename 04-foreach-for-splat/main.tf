terraform {
  required_version = ">= 0.14.4"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.28.0"
    }
  }
}

provider "aws" {
  region                       = var.aws_region
  profile                      = var.aws_profile
  skip_credentials_validation   = true
  skip_requesting_account_id    = true
  skip_metadata_api_check       = true
}
