# ─────────────────────────────────────────────
# Networking State 참조 (VPC, Subnet, SG 가져오기)
# ─────────────────────────────────────────────
data "terraform_remote_state" "networking" {
  backend = "s3"
  config = {
    bucket = "myapp-flab-prd"
    key    = "prod/networking/terraform.tfstate"
    region = "ap-northeast-2"
  }
}

# ─────────────────────────────────────────────
# 랜덤 패스워드 생성
# ─────────────────────────────────────────────
resource "random_password" "db_master" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# ─────────────────────────────────────────────
# Secrets Manager (DB 패스워드 저장)
# ─────────────────────────────────────────────
resource "aws_secretsmanager_secret" "db_master" {
  name        = "${var.project_name}/rds/master-password"
  description = "Aurora MySQL master password for ${var.project_name}"

  tags = {
    Name        = "${var.project_name}-rds-secret"
    Description = "RDS Aurora MySQL master password"
    Tier        = "database"
  }
}

resource "aws_secretsmanager_secret_version" "db_master" {
  secret_id = aws_secretsmanager_secret.db_master.id
  secret_string = jsonencode({
    username = var.db_master_username
    password = random_password.db_master.result
    dbname   = var.db_name
  })
}

# ─────────────────────────────────────────────
# DB Subnet Group
# ─────────────────────────────────────────────
resource "aws_db_subnet_group" "main" {
  name        = "${var.project_name}-db-subnet-group"
  description = "DB Subnet Group for ${var.project_name} Aurora MySQL"
  subnet_ids  = data.terraform_remote_state.networking.outputs.db_subnet_ids

  tags = {
    Name        = "${var.project_name}-db-subnet-group"
    Description = "Subnet group for Aurora MySQL"
    Tier        = "database"
  }
}

# ─────────────────────────────────────────────
# DB Cluster Parameter Group
# ─────────────────────────────────────────────
resource "aws_rds_cluster_parameter_group" "main" {
  name        = "${var.project_name}-cluster-pg"
  family      = "aurora-mysql8.0"
  description = "Aurora MySQL 8.0 Cluster Parameter Group"

  # 한국어 지원 (UTF8MB4)
  parameter {
    name  = "character_set_server"
    value = "utf8mb4"
  }
  parameter {
    name  = "character_set_client"
    value = "utf8mb4"
  }
  parameter {
    name  = "collation_server"
    value = "utf8mb4_unicode_ci"
  }
  # 슬로우 쿼리 로깅
  parameter {
    name  = "slow_query_log"
    value = "1"
  }
  parameter {
    name  = "long_query_time"
    value = "2"
  }

  tags = {
    Name        = "${var.project_name}-cluster-pg"
    Description = "Aurora MySQL cluster parameter group"
    Tier        = "database"
  }
}

# ─────────────────────────────────────────────
# DB Instance Parameter Group
# ─────────────────────────────────────────────
resource "aws_db_parameter_group" "main" {
  name        = "${var.project_name}-db-pg"
  family      = "aurora-mysql8.0"
  description = "Aurora MySQL 8.0 Instance Parameter Group"

  tags = {
    Name        = "${var.project_name}-db-pg"
    Description = "Aurora MySQL instance parameter group"
    Tier        = "database"
  }
}

# ─────────────────────────────────────────────
# Aurora MySQL Cluster
# ─────────────────────────────────────────────
resource "aws_rds_cluster" "main" {
  cluster_identifier = "${var.project_name}-aurora-cluster"
  engine             = "aurora-mysql"
  engine_version     = "8.0.mysql_aurora.3.04.0"
  database_name      = var.db_name
  master_username    = var.db_master_username
  master_password    = random_password.db_master.result

  # 네트워크
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [data.terraform_remote_state.networking.outputs.rds_sg_id]

  # 파라미터 그룹
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.main.name

  # 스토리지 암호화
  storage_encrypted = true

  # 백업 설정
  backup_retention_period   = 7       # 7일 백업 보관
  preferred_backup_window   = "18:00-19:00"  # UTC (한국 새벽 3-4시)
  preferred_maintenance_window = "sun:19:00-sun:20:00"  # UTC (한국 새벽 4-5시)

  # 삭제 보호
  deletion_protection = true

  # 자동 마이너 버전 업그레이드
  enable_http_endpoint          = false
  copy_tags_to_snapshot         = true

  # CloudWatch 로그 활성화
  enabled_cloudwatch_logs_exports = ["audit", "error", "slowquery"]

  # 최종 스냅샷
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.project_name}-aurora-final-snapshot"

  tags = {
    Name        = "${var.project_name}-aurora-cluster"
    Description = "Aurora MySQL cluster for ${var.project_name}"
    Tier        = "database"
  }
}

# ─────────────────────────────────────────────
# Aurora MySQL Instances (Writer 1 + Reader 1)
# ─────────────────────────────────────────────
resource "aws_rds_cluster_instance" "writer" {
  identifier         = "${var.project_name}-aurora-writer"
  cluster_identifier = aws_rds_cluster.main.id
  instance_class     = var.db_instance_class
  engine             = aws_rds_cluster.main.engine
  engine_version     = aws_rds_cluster.main.engine_version

  db_parameter_group_name = aws_db_parameter_group.main.name

  # 유지보수 시간
  preferred_maintenance_window = "sun:19:00-sun:20:00"

  # 자동 마이너 버전 업그레이드
  auto_minor_version_upgrade = true

  # 성능 개선 도우미
  performance_insights_enabled = true

  # Enhanced Monitoring
  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn

  tags = {
    Name        = "${var.project_name}-aurora-writer"
    Description = "Aurora MySQL writer instance"
    Tier        = "database"
    Role        = "writer"
  }
}

resource "aws_rds_cluster_instance" "reader" {
  identifier         = "${var.project_name}-aurora-reader"
  cluster_identifier = aws_rds_cluster.main.id
  instance_class     = var.db_instance_class
  engine             = aws_rds_cluster.main.engine
  engine_version     = aws_rds_cluster.main.engine_version

  db_parameter_group_name = aws_db_parameter_group.main.name

  preferred_maintenance_window = "sun:19:00-sun:20:00"
  auto_minor_version_upgrade   = true
  performance_insights_enabled = true

  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn

  tags = {
    Name        = "${var.project_name}-aurora-reader"
    Description = "Aurora MySQL reader instance"
    Tier        = "database"
    Role        = "reader"
  }
}

# ─────────────────────────────────────────────
# Enhanced Monitoring IAM Role
# ─────────────────────────────────────────────
resource "aws_iam_role" "rds_monitoring" {
  name = "${var.project_name}-rds-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-rds-monitoring-role"
    Description = "IAM role for RDS Enhanced Monitoring"
    Tier        = "database"
  }
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# ─────────────────────────────────────────────
# CloudWatch Alarms
# ─────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "db_cpu" {
  alarm_name          = "${var.project_name}-rds-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "RDS CPU 사용률 80% 초과"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.main.cluster_identifier
  }

  tags = {
    Name        = "${var.project_name}-rds-cpu-alarm"
    Description = "RDS CPU utilization alarm"
    Tier        = "monitoring"
  }
}

resource "aws_cloudwatch_metric_alarm" "db_connections" {
  alarm_name          = "${var.project_name}-rds-connections-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 1000
  alarm_description   = "RDS 연결 수 1000 초과"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.main.cluster_identifier
  }

  tags = {
    Name        = "${var.project_name}-rds-connections-alarm"
    Description = "RDS connections alarm"
    Tier        = "monitoring"
  }
}