terraform {
  required_version = ">= 0.14.4"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.28.0"
    }
  }

  backend "s3" {
    bucket  = "tfstate-594593752477"
    key     = "dev/03-data-sources-s3/terraform.tfstate"
    region  = "eu-central-1"
    profile = "tf014"
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}
