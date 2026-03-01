# ─────────────────────────────────────────────
# Remote State 참조
# ─────────────────────────────────────────────
data "terraform_remote_state" "ecs" {
  backend = "s3"
  config = {
    bucket = "myapp-flab-prd"
    key    = "prod/ecs/terraform.tfstate"
    region = "ap-northeast-2"
  }
}

data "terraform_remote_state" "waf" {
  backend = "s3"
  config = {
    bucket = "myapp-flab-prd"
    key    = "prod/waf/terraform.tfstate"
    region = "ap-northeast-2"
  }
}

# ─────────────────────────────────────────────
# CloudFront용 WAF (us-east-1 전용)
# ─────────────────────────────────────────────
resource "aws_wafv2_web_acl" "cloudfront" {
  provider    = aws.us_east_1
  name        = "${var.project_name}-cloudfront-waf"
  description = "WAF Web ACL for CloudFront ${var.project_name}"
  scope       = "CLOUDFRONT"   # CloudFront는 CLOUDFRONT scope

  default_action {
    allow {}
  }

  # AWS 관리형 규칙 - 공통
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "CloudFrontCommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  # AWS 관리형 규칙 - 악성 IP
  rule {
    name     = "AWSManagedRulesAmazonIpReputationList"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "CloudFrontIpReputationList"
      sampled_requests_enabled   = true
    }
  }

  # Rate Limiting
  rule {
    name     = "RateLimitRule"
    priority = 3

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 3000
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "CloudFrontRateLimitRule"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-cloudfront-waf"
    sampled_requests_enabled   = true
  }

  tags = {
    Name        = "${var.project_name}-cloudfront-waf"
    Description = "WAF for CloudFront"
    Tier        = "security"
  }
}

# ─────────────────────────────────────────────
# ACM Certificate (CloudFront용 - us-east-1 필수)
# ─────────────────────────────────────────────
data "aws_route53_zone" "main" {
  name         = var.domain_name
  private_zone = false
}

resource "aws_acm_certificate" "cloudfront" {
  provider                  = aws.us_east_1
  domain_name               = var.domain_name
  subject_alternative_names = ["*.${var.domain_name}"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name        = "${var.project_name}-cloudfront-acm"
    Description = "ACM Certificate for CloudFront"
    Tier        = "public"
  }
}

# ACM DNS 검증 레코드
resource "aws_route53_record" "cloudfront_acm_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cloudfront.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id         = data.aws_route53_zone.main.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "cloudfront" {
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.cloudfront.arn
  validation_record_fqdns = [for record in aws_route53_record.cloudfront_acm_validation : record.fqdn]
}

# ─────────────────────────────────────────────
# CloudFront Distribution
# ─────────────────────────────────────────────
resource "aws_cloudfront_distribution" "main" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${var.project_name} CloudFront Distribution"
  aliases             = [var.domain_name, "www.${var.domain_name}"]
  web_acl_id          = aws_wafv2_web_acl.cloudfront.arn
  price_class         = "PriceClass_200"  # 미국, 유럽, 아시아

  # ─── Origin (ALB) ───
  origin {
    domain_name = data.terraform_remote_state.ecs.outputs.alb_dns_name
    origin_id   = "${var.project_name}-alb-origin"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"   # ALB → HTTPS만 허용
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    custom_header {
      name  = "X-Custom-Header"
      value = "${var.project_name}-cloudfront"  # ALB에서 CloudFront 요청 식별용
    }
  }

  # ─── 기본 캐시 동작 ───
  default_cache_behavior {
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "${var.project_name}-alb-origin"
    viewer_protocol_policy = "redirect-to-https"   # HTTP → HTTPS 리다이렉트
    compress               = true

    forwarded_values {
      query_string = true
      headers      = ["Host", "Authorization", "CloudFront-Forwarded-Proto"]

      cookies {
        forward = "all"
      }
    }

    min_ttl     = 0
    default_ttl = 0      # API는 캐시 안 함
    max_ttl     = 0
  }

  # ─── 정적 파일 캐시 동작 (/static/*) ───
  ordered_cache_behavior {
    path_pattern           = "/static/*"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "${var.project_name}-alb-origin"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl     = 86400     # 1일
    default_ttl = 604800    # 7일
    max_ttl     = 31536000  # 1년
  }

  # ─── SSL 인증서 ───
  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.cloudfront.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  # ─── 지역 제한 (선택사항) ───
  restrictions {
    geo_restriction {
      restriction_type = "none"   # 전 세계 허용
    }
  }

  # ─── 커스텀 에러 페이지 ───
  custom_error_response {
    error_code            = 403
    response_code         = 403
    response_page_path    = "/error/403.html"
    error_caching_min_ttl = 10
  }

  custom_error_response {
    error_code            = 404
    response_code         = 404
    response_page_path    = "/error/404.html"
    error_caching_min_ttl = 10
  }

  tags = {
    Name        = "${var.project_name}-cloudfront"
    Description = "CloudFront Distribution for ${var.project_name}"
    Tier        = "public"
  }

  depends_on = [aws_acm_certificate_validation.cloudfront]
}

# ─────────────────────────────────────────────
# Route53 레코드 → CloudFront 연결
# ─────────────────────────────────────────────
resource "aws_route53_record" "cloudfront" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "cloudfront_www" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "www.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false
  }
}