terraform {
  required_version = ">= 1.11"

    backend "s3" {
    bucket       = "uptime-monitor-tfstate-533267195508"
    key          = "uptime-monitor/terraform.tfstate"
    region       = "eu-west-2"
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "eu-west-2"

  default_tags {
    tags = {
      Project   = "uptime-monitor"
      ManagedBy = "terraform"
    }
  }
}
