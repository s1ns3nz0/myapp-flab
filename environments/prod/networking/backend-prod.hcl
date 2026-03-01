bucket         = "myapp-flab-prd"
key            = "prod/networking/terraform.tfstate"
region         = "ap-northeast-2"
encrypt        = true
dynamodb_table = "terraform-state-locks"