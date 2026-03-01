bucket         = "myapp-flab-prd"
key            = "prod/waf/terraform.tfstate"
region         = "ap-northeast-2"
encrypt        = true
dynamodb_table = "terraform-state-locks"