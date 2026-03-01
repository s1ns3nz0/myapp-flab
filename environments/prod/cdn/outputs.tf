output "cloudfront_domain_name" {
  description = "CloudFront 도메인 이름"
  value       = aws_cloudfront_distribution.main.domain_name
}

output "cloudfront_distribution_id" {
  description = "CloudFront Distribution ID"
  value       = aws_cloudfront_distribution.main.id
}

output "cloudfront_arn" {
  description = "CloudFront ARN"
  value       = aws_cloudfront_distribution.main.arn
}

output "app_url" {
  description = "앱 접속 URL"
  value       = "https://${var.domain_name}"
}