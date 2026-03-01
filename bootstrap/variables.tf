variable "aws_region" {
  description = "AWS 리전"
  type        = string
  default     = "ap-northeast-2"  # 서울 리전
}

variable "project_name" {
  description = "프로젝트 이름 (버킷 이름에 사용)"
  type        = string
}

variable "bucket_name" {
  description = "Terraform State를 저장할 S3 버킷 이름"
  type        = string
}

variable "dynamodb_table_name" {
  description = "State Locking에 사용할 DynamoDB 테이블 이름"
  type        = string
  default     = "terraform-state-locks"
}

variable "tags" {
  description = "공통 태그"
  type        = map(string)
  default = {
    ManagedBy   = "terraform"
    Environment = "global"
  }
}