variable "aws_region" {
  type    = string
  default = "ap-northeast-2"
}

variable "project_name" {
  type    = string
  default = "myapp-flab-prd"
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