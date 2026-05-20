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
  region = var.aws_region
}

resource "aws_s3_bucket" "my-test-bucket" {
  bucket = "my-tf-test-bucket-123wssoutros"

  tags = {
    Name        = "My first bucket"
    Environment = "Dev"
    ManagedBy   = "Terraform"
    Owner       = "Walyson Silva"
    Updated     = "2026-05-18"
  }
}

resource "aws_instance" "example" {
  ami           = var.instance_ami
  instance_type = var.instance_type

  tags = var.instance_tags
}
