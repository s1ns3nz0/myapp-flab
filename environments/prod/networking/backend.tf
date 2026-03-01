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

  # 모든 리소스에 공통 태그 자동 적용
  default_tags {
    tags = var.tags
  }
}