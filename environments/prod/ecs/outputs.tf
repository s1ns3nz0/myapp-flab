output "alb_dns_name" {
  description = "ALB DNS 이름"
  value       = aws_lb.main.dns_name
}

output "alb_arn" {
  description = "ALB ARN (WAF 연결 시 사용)"
  value       = aws_lb.main.arn
}

output "alb_zone_id" {
  description = "ALB Zone ID"
  value       = aws_lb.main.zone_id
}

output "ecs_cluster_name" {
  description = "ECS 클러스터 이름"
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  description = "ECS 서비스 이름"
  value       = aws_ecs_service.app.name
}

output "ecs_task_definition_arn" {
  description = "ECS Task Definition ARN"
  value       = aws_ecs_task_definition.app.arn
}

output "acm_certificate_arn" {
  description = "ACM 인증서 ARN (CloudFront에서 사용)"
  value       = aws_acm_certificate_validation.main.certificate_arn
}

output "route53_zone_id" {
  description = "Route53 Hosted Zone ID"
  value       = data.aws_route53_zone.main.zone_id
}

output "route53_name_servers" {
  description = "⚠️ 도메인 등록업체에 등록해야 할 네임서버"
  value       = data.aws_route53_zone.main.name_servers
}

output "app_url" {
  description = "앱 접속 URL"
  value       = "https://${var.domain_name}"
}