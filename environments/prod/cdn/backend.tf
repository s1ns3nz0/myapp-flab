terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    region  = "ap-northeast-2"
    encrypt = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = var.tags
  }
}

# ⚠️ CloudFront WAF는 반드시 us-east-1 리전이어야 함
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}