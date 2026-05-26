terraform {
  required_version = ">= 0.14.4"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.28.0"
    }
  }
  backend "s3" {
   
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

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "remote-state" {
  bucket = "tfstate-${data.aws_caller_identity.current.account_id}"
  force_destroy = true

  tags = {
    Description = "Stores terraform remote state files"
    ManagedBy   = "Terraform"
    Owner       = "Cleber Gasparoto"
    CreatedAt   = "2021-01-24"
  }
}

resource "aws_s3_bucket_versioning" "remote_state" {
  bucket = aws_s3_bucket.remote-state.id

  versioning_configuration {
    status = "Enabled"
  }
}