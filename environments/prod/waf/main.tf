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

# ─────────────────────────────────────────────
# WAF IP Set (차단할 IP 목록)
# ─────────────────────────────────────────────
resource "aws_wafv2_ip_set" "blocklist" {
  name               = "${var.project_name}-blocklist"
  description        = "IP blocklist for ${var.project_name}"  # ← 영문으로 변경
  scope              = "REGIONAL"
  ip_address_version = "IPV4"
  addresses          = []

  tags = {
    Name        = "${var.project_name}-waf-blocklist"
    Description = "WAF IP blocklist"
    Tier        = "security"
  }
}

# ─────────────────────────────────────────────
# WAF Web ACL
# ─────────────────────────────────────────────
resource "aws_wafv2_web_acl" "main" {
  name        = "${var.project_name}-waf"
  description = "WAF Web ACL for ${var.project_name}"
  scope       = "REGIONAL"

  # 기본 액션: 허용
  default_action {
    allow {}
  }

  # ─── Rule 1: AWS 관리형 규칙 - 공통 규칙 ───
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}   # 관리형 규칙의 기본 액션 사용
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesCommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  # ─── Rule 2: AWS 관리형 규칙 - 알려진 악성 IP ───
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
      metric_name                = "AWSManagedRulesAmazonIpReputationList"
      sampled_requests_enabled   = true
    }
  }

  # ─── Rule 3: AWS 관리형 규칙 - SQL Injection ───
  rule {
    name     = "AWSManagedRulesSQLiRuleSet"
    priority = 3

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesSQLiRuleSet"
      sampled_requests_enabled   = true
    }
  }

  # ─── Rule 4: AWS 관리형 규칙 - 알려진 악성 입력 ───
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 4

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesKnownBadInputsRuleSet"
      sampled_requests_enabled   = true
    }
  }

  # ─── Rule 5: Rate Limiting (DDoS 방어) ───
  rule {
    name     = "RateLimitRule"
    priority = 5

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 2000   # 5분당 2000 요청 초과 시 차단
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimitRule"
      sampled_requests_enabled   = true
    }
  }

  # ─── Rule 6: 차단 IP 목록 ───
  rule {
    name     = "BlocklistRule"
    priority = 6

    action {
      block {}
    }

    statement {
      ip_set_reference_statement {
        arn = aws_wafv2_ip_set.blocklist.arn
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "BlocklistRule"
      sampled_requests_enabled   = true
    }
  }

  # ─── Rule 7: AWS 관리형 규칙 - Linux ───
  rule {
    name     = "AWSManagedRulesLinuxRuleSet"
    priority = 7

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesLinuxRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesLinuxRuleSet"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-waf"
    sampled_requests_enabled   = true
  }

  tags = {
    Name        = "${var.project_name}-waf"
    Description = "WAF Web ACL for ${var.project_name}"
    Tier        = "security"
  }
}

# ─────────────────────────────────────────────
# WAF → ALB 연결
# ─────────────────────────────────────────────
resource "aws_wafv2_web_acl_association" "alb" {
  resource_arn = data.terraform_remote_state.ecs.outputs.alb_arn
  web_acl_arn  = aws_wafv2_web_acl.main.arn
}

# ─────────────────────────────────────────────
# WAF 로깅 (CloudWatch)
# ─────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "waf" {
  name              = "aws-waf-logs-${var.project_name}"   # 반드시 aws-waf-logs- 로 시작해야 함
  retention_in_days = 30

  tags = {
    Name        = "${var.project_name}-waf-logs"
    Description = "WAF log group"
    Tier        = "security"
  }
}

resource "aws_wafv2_web_acl_logging_configuration" "main" {
  log_destination_configs = [aws_cloudwatch_log_group.waf.arn]
  resource_arn            = aws_wafv2_web_acl.main.arn
}