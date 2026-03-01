output "waf_arn" {
  description = "WAF Web ACL ARN (CloudFront 연결 시 사용)"
  value       = aws_wafv2_web_acl.main.arn
}

output "waf_id" {
  description = "WAF Web ACL ID"
  value       = aws_wafv2_web_acl.main.id
}

output "waf_name" {
  description = "WAF Web ACL 이름"
  value       = aws_wafv2_web_acl.main.name
}