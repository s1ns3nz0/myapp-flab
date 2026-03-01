variable "aws_region" {
  type    = string
  default = "ap-northeast-2"
}

variable "project_name" {
  type    = string
  default = "myapp-flab-prd"
}

variable "domain_name" {
  type    = string
  default = "miata.cloud"
}

variable "ec2_instance_type" {
  description = "ECS EC2 인스턴스 타입"
  type        = string
  default     = "t3.medium"
}

variable "ec2_min_size" {
  description = "Auto Scaling 최소 인스턴스 수"
  type        = number
  default     = 2
}

variable "ec2_max_size" {
  description = "Auto Scaling 최대 인스턴스 수"
  type        = number
  default     = 4
}

variable "ec2_desired_capacity" {
  description = "Auto Scaling 원하는 인스턴스 수"
  type        = number
  default     = 2
}

variable "container_port" {
  description = "컨테이너 포트"
  type        = number
  default     = 8080
}

variable "container_cpu" {
  description = "Task CPU"
  type        = number
  default     = 512
}

variable "container_memory" {
  description = "Task Memory (MB)"
  type        = number
  default     = 1024
}

variable "tags" {
  type = map(string)
  default = {
    Environment  = "prod"
    Project      = "myapp-flab"
    Owner        = "jsyang"
    ManagedBy    = "terraform"
    CostCenter   = "myapp-001"
    BusinessUnit = "engineering"
    Criticality  = "high"
    Backup       = "true"
    DataClass    = "confidential"
  }
}