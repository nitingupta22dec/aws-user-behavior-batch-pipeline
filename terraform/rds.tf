resource "random_password" "db_password" {
  length  = 20
  special = false # keep it simple to paste into connection strings/UIs without escaping
}

resource "aws_db_instance" "source" {
  identifier     = "${var.project_name}-postgres"
  engine         = "postgres"
  engine_version = "16"
  instance_class = var.rds_instance_class

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db_password.result

  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = true # default VPC + my-IP-only SG, so we can reach it directly from our laptop

  skip_final_snapshot = true # fine for a learning project; would be false in production
  deletion_protection = false

  tags = {
    Name = "${var.project_name}-postgres"
  }
}
