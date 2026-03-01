variable "aws_region" {
  type    = string
  default = "ap-northeast-2"
}

variable "project_name" {
  type    = string
  default = "myapp-flab-prd"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "db_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.21.0/24", "10.0.22.0/24"]
}

variable "availability_zones" {
  type    = list(string)
  default = ["ap-northeast-2a", "ap-northeast-2c"]
}

# ─────────────────────────────────────────────
# 공통 태그
# ─────────────────────────────────────────────
variable "tags" {
  description = "공통 태그"
  type        = map(string)
  default = {
    # 필수 태그
    Environment = "prod"
    Project     = "myapp-flab"
    Owner       = "devops-team"
    ManagedBy   = "terraform"

    # 비용 관리
    CostCenter  = "myapp-001"
    BusinessUnit = "engineering"

    # 운영
    Criticality = "high"
    Backup      = "true"

    # 보안
    DataClass   = "confidential"
  }
}