bucket         = "myapp-flab-prd"
key            = "prod/cdn/terraform.tfstate"
region         = "ap-northeast-2"
encrypt        = true
dynamodb_table = "terraform-state-locks"