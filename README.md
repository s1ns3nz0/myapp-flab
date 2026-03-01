# myapp-flab Production Infrastructure

AWS 기반 프로덕션 인프라 및 FastAPI 애플리케이션 구성 문서입니다.

---

## 📋 목차

- [전체 아키텍처](#전체-아키텍처)
- [인프라 구성](#인프라-구성)
- [보안 구성](#보안-구성)
- [애플리케이션](#애플리케이션)
- [CI/CD 파이프라인](#cicd-파이프라인)
- [Terraform State 구조](#terraform-state-구조)
- [폴더 구조](#폴더-구조)
- [비용 예상](#비용-예상)
- [주요 명령어](#주요-명령어)

---

## 전체 아키텍처

```
Internet
    │
    ▼
┌─────────────────────────────────────┐
│  CloudFront (dp10wgzqc2ci7.cf.net)  │
│  - WAF (CLOUDFRONT scope)           │
│  - ACM 인증서 (us-east-1)           │
│  - Price Class 200                  │
│  - 정적 파일 캐시 (/static/*)       │
└──────────────┬──────────────────────┘
               │ HTTPS
               ▼
┌─────────────────────────────────────┐
│  Route53 (miata.cloud)              │
│  - Hosted Zone                      │
│  - A Record → CloudFront Alias      │
│  - www A Record → CloudFront Alias  │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│  WAF (REGIONAL scope)               │
│  - CommonRuleSet                    │
│  - IpReputationList                 │
│  - SQLiRuleSet                      │
│  - KnownBadInputsRuleSet            │
│  - RateLimit (2000 req/5min)        │
│  - IP Blocklist                     │
│  - LinuxRuleSet                     │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────────────────────┐
│  VPC (10.0.0.0/16)  ap-northeast-2                  │
│                                                     │
│  ┌──────────────────────────────────────────────┐  │
│  │  Public Subnet                               │  │
│  │  AZ-a: 10.0.1.0/24  AZ-c: 10.0.2.0/24      │  │
│  │                                              │  │
│  │  ┌───────────────────────────────────────┐   │  │
│  │  │  ALB (myapp-flab-prd-alb)             │   │  │
│  │  │  - HTTP(80)  → HTTPS 리다이렉트       │   │  │
│  │  │  - HTTPS(443) → Target Group          │   │  │
│  │  │  - ACM 인증서 (ap-northeast-2)        │   │  │
│  │  └───────────────────────────────────────┘   │  │
│  │  NAT GW (AZ-a)        NAT GW (AZ-c)          │  │
│  └──────────────────────────────────────────────┘  │
│                                                     │
│  ┌──────────────────────────────────────────────┐  │
│  │  Private Subnet                              │  │
│  │  AZ-a: 10.0.11.0/24  AZ-c: 10.0.12.0/24    │  │
│  │                                              │  │
│  │  ┌───────────────────────────────────────┐   │  │
│  │  │  ECS Cluster (EC2 기반)               │   │  │
│  │  │  EC2 Instance (t3.medium)             │   │  │
│  │  │  ├── Container: FastAPI (port 8080)   │   │  │
│  │  │  └── Container: FastAPI (port 8080)   │   │  │
│  │  │  Auto Scaling Group (min:2 max:4)     │   │  │
│  │  │  Capacity Provider                    │   │  │
│  │  └───────────────────────────────────────┘   │  │
│  └──────────────────────────────────────────────┘  │
│                                                     │
│  ┌──────────────────────────────────────────────┐  │
│  │  DB Subnet                                   │  │
│  │  AZ-a: 10.0.21.0/24  AZ-c: 10.0.22.0/24    │  │
│  │                                              │  │
│  │  ┌───────────────────────────────────────┐   │  │
│  │  │  Aurora MySQL 8.0                     │   │  │
│  │  │  - Writer: db.r6g.large               │   │  │
│  │  │  - Reader: db.r6g.large               │   │  │
│  │  │  - DB: myappdb                        │   │  │
│  │  │  - 패스워드: Secrets Manager          │   │  │
│  │  └───────────────────────────────────────┘   │  │
│  └──────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
```

---

## 인프라 구성

### Bootstrap
| 리소스 | 이름 | 설명 |
|---|---|---|
| S3 Bucket | myapp-flab-prd | Terraform State 저장소 |
| DynamoDB | terraform-state-locks | State 잠금 |
| KMS | myapp-flab-prd-key | State 암호화 |

### Networking
| 리소스 | CIDR | 설명 |
|---|---|---|
| VPC | 10.0.0.0/16 | 메인 VPC |
| Public Subnet AZ-a | 10.0.1.0/24 | ALB, NAT Gateway |
| Public Subnet AZ-c | 10.0.2.0/24 | ALB, NAT Gateway |
| Private Subnet AZ-a | 10.0.11.0/24 | ECS EC2 |
| Private Subnet AZ-c | 10.0.12.0/24 | ECS EC2 |
| DB Subnet AZ-a | 10.0.21.0/24 | Aurora MySQL |
| DB Subnet AZ-c | 10.0.22.0/24 | Aurora MySQL |

### ECS
| 항목 | 값 |
|---|---|
| Launch Type | EC2 |
| Instance Type | t3.medium |
| Min Size | 2 |
| Max Size | 4 |
| Container Port | 8080 |
| CPU | 512 |
| Memory | 1024 MB |

### RDS Aurora MySQL
| 항목 | 값 |
|---|---|
| Engine | aurora-mysql 8.0 |
| Writer | db.r6g.large |
| Reader | db.r6g.large |
| Database | myappdb |
| Username | admin |
| Password | Secrets Manager |
| Backup Retention | 7일 |

### ECR
| 항목 | 값 |
|---|---|
| Repository | myapp-flab-prd-app |
| Tag Mutability | MUTABLE |
| Scan on Push | 활성화 |
| Lifecycle | 태그 이미지 30개 유지, 미태그 7일 후 삭제 |

---

## 보안 구성

### Security Group
| 보안그룹 | 인바운드 | 출처 |
|---|---|---|
| ALB SG | 80, 443 | 0.0.0.0/0 |
| ECS SG | 32768-65535 | ALB SG |
| RDS SG | 3306 | ECS SG |

### NACL
| NACL | 허용 포트 | 설명 |
|---|---|---|
| Public | 80, 443, 1024-65535 | HTTP/HTTPS + Ephemeral |
| Private | 8080, 1024-65535 | App + Ephemeral |
| DB | 3306 | MySQL (Private Subnet에서만) |

### WAF 규칙
| 우선순위 | 규칙 | 목적 |
|---|---|---|
| 1 | AWSManagedRulesCommonRuleSet | 일반 웹 공격 차단 |
| 2 | AWSManagedRulesAmazonIpReputationList | 악성 IP 차단 |
| 3 | AWSManagedRulesSQLiRuleSet | SQL Injection 차단 |
| 4 | AWSManagedRulesKnownBadInputsRuleSet | 악성 입력값 차단 |
| 5 | RateLimitRule | DDoS 방어 (2000 req/5min) |
| 6 | BlocklistRule | 수동 IP 차단 |
| 7 | AWSManagedRulesLinuxRuleSet | Linux 취약점 차단 |

### IAM
| Role | 용도 |
|---|---|
| ECS Task Execution Role | ECR Pull, CloudWatch 로그, Secrets Manager 접근 |
| ECS Instance Role | ECS 클러스터 등록 |

---

## 애플리케이션

### 기술 스택
- **언어**: Python 3.11
- **프레임워크**: FastAPI
- **ORM**: SQLAlchemy
- **DB Driver**: PyMySQL
- **서버**: Uvicorn (port 8080)

### API 엔드포인트
| Method | Path | 설명 |
|---|---|---|
| GET | / | 루트 |
| GET | /health | 헬스체크 (DB 연결 포함) |
| GET | /items | 아이템 목록 조회 |
| GET | /items/{id} | 아이템 단건 조회 |
| POST | /items | 아이템 생성 |
| DELETE | /items/{id} | 아이템 삭제 |
| GET | /docs | Swagger UI |

### API 테스트

```bash
# 헬스체크
curl https://miata.cloud/health

# 아이템 생성
curl -X POST https://miata.cloud/items \
  -H "Content-Type: application/json" \
  -d '{"name": "테스트", "description": "설명"}'

# 아이템 목록 조회
curl https://miata.cloud/items

# 아이템 삭제
curl -X DELETE https://miata.cloud/items/1

# Swagger UI
open https://miata.cloud/docs
```

### 환경변수
| 변수명 | 설명 | 출처 |
|---|---|---|
| APP_ENV | 실행 환경 (prod/local) | ECS Task Definition |
| DB_HOST | Aurora Writer 엔드포인트 | ECS Task Definition |
| DB_PORT | DB 포트 (3306) | ECS Task Definition |
| DB_NAME | DB 이름 (myappdb) | ECS Task Definition |
| DB_SECRET | Secrets Manager ARN | ECS Task Definition (secrets) |

---

## CI/CD 파이프라인

### 흐름

```
git push origin main
        │
        ▼
┌───────────────────┐
│ Job 1: Checkov    │  Terraform 보안 검사 (soft-fail)
└────────┬──────────┘
         │
┌────────▼──────────┐
│ Job 2: Test       │  pytest 실행
└────────┬──────────┘
         │
┌────────▼──────────┐
│ Job 3: Build      │  Docker 빌드 & ECR 푸시 (커밋 SHA 태그)
└────────┬──────────┘
         │
┌────────▼──────────┐
│ Job 4: Deploy     │  ECS Rolling Update
└────────┬──────────┘
         │
         ▼
https://miata.cloud ✅
```

### 배포 전략 (Rolling Update)
| 항목 | 값 | 설명 |
|---|---|---|
| Minimum Healthy | 50% | 배포 중 최소 1개 유지 |
| Maximum Percent | 200% | 최대 4개까지 동시 실행 |
| Circuit Breaker | 활성화 | 배포 실패 시 자동 롤백 |

### GitHub Secrets
| Secret | 설명 |
|---|---|
| AWS_ACCESS_KEY_ID | AWS IAM 액세스 키 |
| AWS_SECRET_ACCESS_KEY | AWS IAM 시크릿 키 |

---

## Terraform State 구조

```
S3: myapp-flab-prd
├── global/
│   └── bootstrap/terraform.tfstate     # S3, DynamoDB, KMS
└── prod/
    ├── main/terraform.tfstate           # 메인
    ├── networking/terraform.tfstate     # VPC, Subnet, SG, NACL
    ├── ecr/terraform.tfstate            # ECR
    ├── rds/terraform.tfstate            # Aurora MySQL
    ├── ecs/terraform.tfstate            # ECS, ALB, Route53, ACM
    ├── waf/terraform.tfstate            # WAF
    └── cdn/terraform.tfstate            # CloudFront
```

### Backend 초기화

```bash
terraform init -backend-config="backend-prod.hcl"
```

---

## 폴더 구조

```
myapp-flab/
├── .github/
│   └── workflows/
│       └── deploy.yml              # GitHub Actions CI/CD
├── app/
│   ├── main.py                     # FastAPI 앱
│   ├── database.py                 # Aurora MySQL 연결
│   ├── models.py                   # DB 모델
│   ├── requirements.txt            # Python 의존성
│   ├── Dockerfile                  # 컨테이너 이미지
│   └── .env.example                # 환경변수 예시
├── environments/
│   └── prod/
│       ├── networking/             # VPC, Subnet, SG, NACL
│       ├── ecr/                    # ECR
│       ├── rds/                    # Aurora MySQL
│       ├── ecs/                    # ECS, ALB, Route53, ACM
│       ├── waf/                    # WAF
│       └── cdn/                    # CloudFront
├── bootstrap/                      # S3, DynamoDB, KMS
└── .gitignore
```

---

## 비용 예상

| 리소스 | 수량 | 월 예상 비용 |
|---|---|---|
| NAT Gateway | 2 | ~$65 |
| ALB | 1 | ~$20 |
| EC2 t3.medium | 2 | ~$60 |
| Aurora db.r6g.large | 2 | ~$200 |
| CloudFront | - | 트래픽 기반 |
| ECR | - | 스토리지 기반 |
| CloudWatch | - | 사용량 기반 |
| Secrets Manager | 1 | ~$0.5 |

---

## 주요 명령어

### Terraform

```bash
# 초기화
terraform init -backend-config="backend-prod.hcl"

# 계획 확인
terraform plan

# 적용
terraform apply

# 삭제
terraform destroy

# State 확인
aws s3 ls s3://myapp-flab-prd --recursive
```

### ECS

```bash
# 서비스 상태 확인
aws ecs describe-services \
  --cluster myapp-flab-prd-cluster \
  --services myapp-flab-prd-service \
  --region ap-northeast-2 \
  --query 'services[*].{Running:runningCount, Desired:desiredCount}'

# 강제 재배포
aws ecs update-service \
  --cluster myapp-flab-prd-cluster \
  --service myapp-flab-prd-service \
  --force-new-deployment \
  --region ap-northeast-2

# 로그 확인
aws logs tail /ecs/myapp-flab-prd --follow --region ap-northeast-2
```

### ECR

```bash
# ECR 로그인
aws ecr get-login-password --region ap-northeast-2 | \
  docker login --username AWS \
  --password-stdin 106760547719.dkr.ecr.ap-northeast-2.amazonaws.com

# 이미지 목록
aws ecr describe-images \
  --repository-name myapp-flab-prd-app \
  --region ap-northeast-2
```

### GitHub Actions

```bash
# 실행 목록
gh run list --limit 5

# 실시간 로그
gh run watch

# 수동 트리거
git commit --allow-empty -m "chore: trigger deployment"
git push origin main
```

### Checkov

```bash
# 로컬 보안 검사
pip3 install checkov
checkov -d environments/ --framework terraform --compact
```

---

## 참고

- **도메인**: https://miata.cloud
- **Swagger UI**: https://miata.cloud/docs
- **AWS 리전**: ap-northeast-2 (서울)
- **GitHub**: https://github.com/s1ns3nz0/myapp-flab
- **ECR**: 106760547719.dkr.ecr.ap-northeast-2.amazonaws.com/myapp-flab-prd-app
