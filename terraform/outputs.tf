output "ec2_public_ip" {
  description = "Public IP of the Airflow host"
  value       = aws_instance.airflow.public_ip
}

output "ec2_ssh_command" {
  description = "SSH command to reach the Airflow host"
  value       = "ssh -i ~/.ssh/id_ed25519 ec2-user@${aws_instance.airflow.public_ip}"
}

output "rds_endpoint" {
  description = "RDS Postgres connection endpoint"
  value       = aws_db_instance.source.address
}

output "rds_port" {
  value = aws_db_instance.source.port
}

output "db_name" {
  value = aws_db_instance.source.db_name
}

output "db_username" {
  value = aws_db_instance.source.username
}

output "db_password" {
  description = "RDS master password (sensitive; use `terraform output -raw db_password`)"
  value       = random_password.db_password.result
  sensitive   = true
}

output "raw_bucket" {
  value = aws_s3_bucket.raw.bucket
}

output "processed_bucket" {
  value = aws_s3_bucket.processed.bucket
}
