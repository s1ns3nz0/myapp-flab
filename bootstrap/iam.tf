# ─────────────────────────────────────────────
# Terraform Backend 전용 IAM Policy
# ─────────────────────────────────────────────
data "aws_iam_policy_document" "terraform_backend" {

  # S3: 버킷 목록 조회
  statement {
    sid    = "S3ListBucket"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketVersioning"
    ]
    resources = [aws_s3_bucket.terraform_state.arn]
  }

  # S3: State 파일 읽기/쓰기/삭제
  statement {
    sid    = "S3StateAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject"
    ]
    resources = ["${aws_s3_bucket.terraform_state.arn}/*"]
  }

  # DynamoDB: State Lock 관리
  statement {
    sid    = "DynamoDBLocking"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:DeleteItem",
      "dynamodb:DescribeTable"
    ]
    resources = [aws_dynamodb_table.terraform_locks.arn]
  }

  # KMS: State 암호화/복호화
  statement {
    sid    = "KMSAccess"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey",
      "kms:DescribeKey"
    ]
    resources = [aws_kms_key.terraform_state.arn]
  }
}

resource "aws_iam_policy" "terraform_backend" {
  name        = "${var.project_name}-terraform-backend-policy"
  description = "Terraform S3 Backend 최소 권한 정책"
  policy      = data.aws_iam_policy_document.terraform_backend.json
}

# CI/CD용 IAM Role (GitHub Actions, Jenkins 등에서 사용)
resource "aws_iam_role" "terraform_cicd" {
  name = "${var.project_name}-terraform-cicd-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
          # GitHub Actions OIDC 사용 시:
          # Federated = "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "terraform_cicd" {
  role       = aws_iam_role.terraform_cicd.name
  policy_arn = aws_iam_policy.terraform_backend.arn
}