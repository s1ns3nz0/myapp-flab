output "cluster_endpoint" {
  description = "Aurora 클러스터 Writer 엔드포인트 (쓰기용)"
  value       = aws_rds_cluster.main.endpoint
}

output "cluster_reader_endpoint" {
  description = "Aurora 클러스터 Reader 엔드포인트 (읽기용)"
  value       = aws_rds_cluster.main.reader_endpoint
}

output "cluster_identifier" {
  description = "Aurora 클러스터 ID"
  value       = aws_rds_cluster.main.cluster_identifier
}

output "db_name" {
  description = "데이터베이스 이름"
  value       = aws_rds_cluster.main.database_name
}

output "db_port" {
  description = "데이터베이스 포트"
  value       = aws_rds_cluster.main.port
}

output "secret_arn" {
  description = "Secrets Manager ARN (DB 패스워드)"
  value       = aws_secretsmanager_secret.db_master.arn
}