terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

#   처음에는 local backend로 시작
#   생성 완료 후 아래 backend 블록으로 교체 후 terraform init -migrate-state 실행
  backend "s3" {
    bucket         = "myapp-flab-prd"
    key            = "global/bootstrap/terraform.tfstate"
    region         = "ap-northeast-2"
    encrypt        = true
    dynamodb_table = "terraform-state-locks"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = var.tags
  }
}

# ─────────────────────────────────────────────
# KMS Key (State 암호화용)
# ─────────────────────────────────────────────
resource "aws_kms_key" "terraform_state" {
  description             = "KMS key for Terraform state encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true  # 1년마다 자동 키 교체

  tags = {
    Name = "${var.project_name}-terraform-state-kms"
  }
}

resource "aws_kms_alias" "terraform_state" {
  name          = "alias/${var.project_name}-terraform-state"
  target_key_id = aws_kms_key.terraform_state.key_id
}

# ─────────────────────────────────────────────
# S3 Bucket
# ─────────────────────────────────────────────
resource "aws_s3_bucket" "terraform_state" {
  bucket = var.bucket_name

  # 실수로 삭제 방지
  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name = var.bucket_name
  }
}

# 버전 관리 활성화 (이전 state로 롤백 가능)
resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# KMS 서버 사이드 암호화
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.terraform_state.arn
    }
    bucket_key_enabled = true  # KMS 비용 절감
  }
}

# 퍼블릭 접근 완전 차단
resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 접근 로깅
resource "aws_s3_bucket_logging" "terraform_state" {
  bucket        = aws_s3_bucket.terraform_state.id
  target_bucket = aws_s3_bucket.terraform_state.id
  target_prefix = "access-logs/"
}

# 오래된 버전 자동 정리 (90일 후 삭제)
resource "aws_s3_bucket_lifecycle_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  # 현재 버전 이외의 이전 버전 90일 후 삭제
  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    # 완료되지 않은 멀티파트 업로드 7일 후 정리
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# ─────────────────────────────────────────────
# DynamoDB Table (State Locking)
# ─────────────────────────────────────────────
resource "aws_dynamodb_table" "terraform_locks" {
  name         = var.dynamodb_table_name
  billing_mode = "PAY_PER_REQUEST"  # 사용한 만큼만 과금
  hash_key     = "LockID"           # Terraform이 요구하는 필수 키 이름

  attribute {
    name = "LockID"
    type = "S"  # String 타입
  }

  # 실수로 삭제 방지
  lifecycle {
    prevent_destroy = true
  }

  # 특정 시점으로 복구 가능 (PITR)
  point_in_time_recovery {
    enabled = true
  }

  # DynamoDB 암호화
  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.terraform_state.arn
  }

  tags = {
    Name = var.dynamodb_table_name
  }
}