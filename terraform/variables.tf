variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short name used to prefix/tag all resources"
  type        = string
  default     = "de-project"
}

variable "ec2_instance_type" {
  description = "Instance type for the Airflow host"
  type        = string
  default     = "t3.small"
}

variable "rds_instance_class" {
  description = "Instance class for RDS Postgres"
  type        = string
  default     = "db.t3.micro"
}

variable "db_name" {
  description = "Name of the initial Postgres database"
  type        = string
  default     = "sourcedb"
}

variable "db_username" {
  description = "Master username for RDS Postgres"
  type        = string
  default     = "deproject_admin"
}

variable "ssh_public_key_path" {
  description = "Path to the local SSH public key to authorize on the EC2 instance"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}
