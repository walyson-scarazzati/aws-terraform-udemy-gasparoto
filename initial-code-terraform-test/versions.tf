terraform {
  required_version = "~> 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.15"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }

  backend "s3" {
    bucket       = "tfstate-257527264470"
    key          = "dev/06-terraform-test/terraform.tfstate"
    region       = "eu-central-1"
    profile      = "tf014"
    use_lockfile = true
  }
}
