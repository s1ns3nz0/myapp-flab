output "s3_bucket_name" {
  description = "Terraform State S3 버킷 이름"
  value       = aws_s3_bucket.terraform_state.id
}

output "s3_bucket_arn" {
  description = "Terraform State S3 버킷 ARN"
  value       = aws_s3_bucket.terraform_state.arn
}

output "dynamodb_table_name" {
  description = "State Locking DynamoDB 테이블 이름"
  value       = aws_dynamodb_table.terraform_locks.name
}

output "dynamodb_table_arn" {
  description = "State Locking DynamoDB 테이블 ARN"
  value       = aws_dynamodb_table.terraform_locks.arn
}

output "kms_key_arn" {
  description = "State 암호화 KMS 키 ARN"
  value       = aws_kms_key.terraform_state.arn
}

output "backend_config" {
  description = "Backend 설정에 사용할 값들"
  value = {
    bucket         = aws_s3_bucket.terraform_state.id
    region         = var.aws_region
    dynamodb_table = aws_dynamodb_table.terraform_locks.name
    kms_key_id     = aws_kms_key.terraform_state.arn
  }
}