terraform {
  required_version = ">= 1.11"

  backend "s3" {
    bucket       = "uptime-monitor-tfstate-533267195508"
    key          = "uptime-monitor/infra.tfstate"
    region       = "eu-west-2"
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
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

variable "targets" {
  description = "URLs the monitor probes, in priority order"
  type        = list(string)
  default = [
    "https://example.com",
    "https://www.gov.uk",
  ]
}
