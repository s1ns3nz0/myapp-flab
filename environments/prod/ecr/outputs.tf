output "ecr_repository_url" {
  description = "ECR Repository URL (docker push 할 때 사용)"
  value       = aws_ecr_repository.app.repository_url
}

output "ecr_repository_arn" {
  description = "ECR Repository ARN"
  value       = aws_ecr_repository.app.arn
}

output "ecr_repository_name" {
  description = "ECR Repository Name"
  value       = aws_ecr_repository.app.name
}

output "aws_account_id" {
  description = "AWS Account ID"
  value       = data.aws_caller_identity.current.account_id
}