#!/bin/bash

# ─────────────────────────────────────────────
# myapp-flab 전체 인프라 삭제 스크립트
# ─────────────────────────────────────────────

set -e  # 에러 발생 시 스크립트 중단

PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
REGION="ap-northeast-2"

echo "======================================================"
echo "  myapp-flab 인프라 전체 삭제 시작"
echo "  PROJECT_ROOT: $PROJECT_ROOT"
echo "======================================================"
echo ""
echo "⚠️  이 스크립트는 모든 AWS 리소스를 삭제합니다."
read -p "계속 진행하시겠습니까? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
  echo "삭제가 취소되었습니다."
  exit 0
fi

# ─────────────────────────────────────────────
# Step 1. 삭제 방지 옵션 해제
# ─────────────────────────────────────────────
echo ""
echo "[Step 1] 삭제 방지 옵션 해제 중..."

# ALB 삭제 방지 해제
ALB_ARN=$(aws elbv2 describe-load-balancers \
  --names myapp-flab-prd-alb \
  --region $REGION \
  --query 'LoadBalancers[0].LoadBalancerArn' \
  --output text 2>/dev/null || echo "")

if [ -n "$ALB_ARN" ] && [ "$ALB_ARN" != "None" ]; then
  echo "  → ALB 삭제 방지 해제..."
  aws elbv2 modify-load-balancer-attributes \
    --load-balancer-arn $ALB_ARN \
    --attributes Key=deletion_protection.enabled,Value=false \
    --region $REGION
  echo "  ✅ ALB 삭제 방지 해제 완료"
else
  echo "  ℹ️  ALB를 찾을 수 없습니다. 건너뜁니다."
fi

# RDS 삭제 방지 해제
RDS_EXISTS=$(aws rds describe-db-clusters \
  --db-cluster-identifier myapp-flab-prd-aurora-cluster \
  --region $REGION \
  --query 'DBClusters[0].DBClusterIdentifier' \
  --output text 2>/dev/null || echo "")

if [ -n "$RDS_EXISTS" ] && [ "$RDS_EXISTS" != "None" ]; then
  echo "  → RDS 삭제 방지 해제..."
  aws rds modify-db-cluster \
    --db-cluster-identifier myapp-flab-prd-aurora-cluster \
    --no-deletion-protection \
    --apply-immediately \
    --region $REGION
  echo "  ✅ RDS 삭제 방지 해제 완료"
else
  echo "  ℹ️  RDS를 찾을 수 없습니다. 건너뜁니다."
fi

# ASG 삭제 방지 해제
ASG_EXISTS=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names myapp-flab-prd-ecs-asg \
  --region $REGION \
  --query 'AutoScalingGroups[0].AutoScalingGroupName' \
  --output text 2>/dev/null || echo "")

if [ -n "$ASG_EXISTS" ] && [ "$ASG_EXISTS" != "None" ]; then
  echo "  → ASG 삭제 방지 해제..."
  aws autoscaling update-auto-scaling-group \
    --auto-scaling-group-name myapp-flab-prd-ecs-asg \
    --no-new-instances-protected-from-scale-in \
    --region $REGION
  echo "  ✅ ASG 삭제 방지 해제 완료"
else
  echo "  ℹ️  ASG를 찾을 수 없습니다. 건너뜁니다."
fi

# ─────────────────────────────────────────────
# Step 2. CDN 삭제
# ─────────────────────────────────────────────
echo ""
echo "[Step 2] CDN (CloudFront) 삭제 중..."
cd $PROJECT_ROOT/environments/prod/cdn
terraform init -backend-config="backend-prod.hcl" -reconfigure > /dev/null 2>&1
terraform destroy -auto-approve
echo "  ✅ CDN 삭제 완료"

# ─────────────────────────────────────────────
# Step 3. WAF 삭제
# ─────────────────────────────────────────────
echo ""
echo "[Step 3] WAF 삭제 중..."
cd $PROJECT_ROOT/environments/prod/waf
terraform init -backend-config="backend-prod.hcl" -reconfigure > /dev/null 2>&1
terraform destroy -auto-approve
echo "  ✅ WAF 삭제 완료"

# ─────────────────────────────────────────────
# Step 4. ECS 삭제
# ─────────────────────────────────────────────
echo ""
echo "[Step 4] ECS (ALB, Route53, ACM 포함) 삭제 중..."
cd $PROJECT_ROOT/environments/prod/ecs
terraform init -backend-config="backend-prod.hcl" -reconfigure > /dev/null 2>&1
terraform destroy -auto-approve
echo "  ✅ ECS 삭제 완료"

# ─────────────────────────────────────────────
# Step 5. RDS 삭제
# ─────────────────────────────────────────────
echo ""
echo "[Step 5] RDS (Aurora MySQL) 삭제 중..."
cd $PROJECT_ROOT/environments/prod/rds
terraform init -backend-config="backend-prod.hcl" -reconfigure > /dev/null 2>&1
terraform destroy -auto-approve
echo "  ✅ RDS 삭제 완료"

# ─────────────────────────────────────────────
# Step 6. ECR 이미지 삭제 후 ECR 삭제
# ─────────────────────────────────────────────
echo ""
echo "[Step 6] ECR 이미지 및 저장소 삭제 중..."

ECR_EXISTS=$(aws ecr describe-repositories \
  --repository-names myapp-flab-prd-app \
  --region $REGION \
  --query 'repositories[0].repositoryName' \
  --output text 2>/dev/null || echo "")

if [ -n "$ECR_EXISTS" ] && [ "$ECR_EXISTS" != "None" ]; then
  echo "  → ECR 이미지 삭제 중..."
  IMAGE_IDS=$(aws ecr list-images \
    --repository-name myapp-flab-prd-app \
    --region $REGION \
    --query 'imageIds' \
    --output json)

  if [ "$IMAGE_IDS" != "[]" ]; then
    aws ecr batch-delete-image \
      --repository-name myapp-flab-prd-app \
      --region $REGION \
      --image-ids "$IMAGE_IDS" > /dev/null
    echo "  ✅ ECR 이미지 삭제 완료"
  else
    echo "  ℹ️  삭제할 이미지가 없습니다."
  fi
fi

cd $PROJECT_ROOT/environments/prod/ecr
terraform init -backend-config="backend-prod.hcl" -reconfigure > /dev/null 2>&1
terraform destroy -auto-approve
echo "  ✅ ECR 삭제 완료"

# ─────────────────────────────────────────────
# Step 7. Networking 삭제
# ─────────────────────────────────────────────
echo ""
echo "[Step 7] Networking (VPC, Subnet, SG, NACL) 삭제 중..."
cd $PROJECT_ROOT/environments/prod/networking
terraform init -backend-config="backend-prod.hcl" -reconfigure > /dev/null 2>&1
terraform destroy -auto-approve
echo "  ✅ Networking 삭제 완료"

# ─────────────────────────────────────────────
# Step 8. S3 버킷 비우기 (Bootstrap 삭제 전 필수)
# ─────────────────────────────────────────────
echo ""
echo "[Step 8] S3 버킷 비우는 중..."

S3_EXISTS=$(aws s3api head-bucket \
  --bucket myapp-flab-prd \
  --region $REGION 2>/dev/null && echo "exists" || echo "")

if [ -n "$S3_EXISTS" ]; then
  echo "  → S3 객체 삭제 중..."
  aws s3 rm s3://myapp-flab-prd --recursive --region $REGION

  echo "  → S3 버전 객체 삭제 중..."
  VERSIONS=$(aws s3api list-object-versions \
    --bucket myapp-flab-prd \
    --region $REGION \
    --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
    --output json 2>/dev/null)

  if [ "$VERSIONS" != '{"Objects": null}' ] && [ -n "$VERSIONS" ]; then
    aws s3api delete-objects \
      --bucket myapp-flab-prd \
      --delete "$VERSIONS" \
      --region $REGION > /dev/null
  fi

  echo "  → S3 삭제 마커 삭제 중..."
  MARKERS=$(aws s3api list-object-versions \
    --bucket myapp-flab-prd \
    --region $REGION \
    --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' \
    --output json 2>/dev/null)

  if [ "$MARKERS" != '{"Objects": null}' ] && [ -n "$MARKERS" ]; then
    aws s3api delete-objects \
      --bucket myapp-flab-prd \
      --delete "$MARKERS" \
      --region $REGION > /dev/null
  fi

  echo "  ✅ S3 버킷 비우기 완료"
else
  echo "  ℹ️  S3 버킷을 찾을 수 없습니다. 건너뜁니다."
fi

# ─────────────────────────────────────────────
# Step 9. Bootstrap 삭제
# ─────────────────────────────────────────────
echo ""
echo "[Step 9] Bootstrap (S3, DynamoDB, KMS) 삭제 중..."
cd $PROJECT_ROOT/bootstrap
terraform destroy -auto-approve
echo "  ✅ Bootstrap 삭제 완료"

# ─────────────────────────────────────────────
# Step 10. Route53 Hosted Zone 정리 (중복 생성된 경우)
# ─────────────────────────────────────────────
echo ""
echo "[Step 10] Route53 Hosted Zone 확인 중..."
ZONES=$(aws route53 list-hosted-zones \
  --query 'HostedZones[*].{Name:Name, Id:Id}' \
  --output json)

ZONE_COUNT=$(echo $ZONES | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")

if [ "$ZONE_COUNT" -gt "0" ]; then
  echo "  ⚠️  아직 남아있는 Hosted Zone이 있습니다:"
  echo "$ZONES"
  echo "  필요 시 수동으로 삭제해주세요:"
  echo "  aws route53 delete-hosted-zone --id <ZONE_ID>"
else
  echo "  ✅ 삭제할 Hosted Zone 없음"
fi

# ─────────────────────────────────────────────
# 완료
# ─────────────────────────────────────────────
echo ""
echo "======================================================"
echo "  ✅ 전체 인프라 삭제 완료!"
echo "======================================================"
echo ""
echo "최종 확인:"
echo "  aws ec2 describe-vpcs --region $REGION --filters 'Name=tag:Project,Values=myapp-flab' --query 'Vpcs[*].VpcId'"
echo "  aws s3 ls | grep myapp-flab"
echo "  aws ecs describe-clusters --clusters myapp-flab-prd-cluster --region $REGION"
