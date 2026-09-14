data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_key_pair" "airflow" {
  key_name   = "${var.project_name}-key"
  public_key = var.ssh_public_key
}

# IAM role so the EC2 host (and Airflow on it) can reach S3 via an instance
# profile instead of long-lived access keys baked into a config file.
resource "aws_iam_role" "airflow_ec2" {
  name = "${var.project_name}-airflow-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "airflow_ec2_s3" {
  name = "${var.project_name}-airflow-ec2-s3-access"
  role = aws_iam_role.airflow_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListBucket",
        "s3:DeleteObject",
      ]
      Resource = [
        aws_s3_bucket.raw.arn,
        "${aws_s3_bucket.raw.arn}/*",
        aws_s3_bucket.processed.arn,
        "${aws_s3_bucket.processed.arn}/*",
      ]
    }]
  })
}

resource "aws_iam_role_policy" "airflow_ec2_emr" {
  name = "${var.project_name}-airflow-ec2-emr-access"
  role = aws_iam_role.airflow_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SubmitAndMonitorEMRJobs"
        Effect = "Allow"
        Action = [
          "emr-serverless:GetApplication",
          "emr-serverless:StartJobRun",
          "emr-serverless:GetJobRun",
          "emr-serverless:CancelJobRun",
        ]
        Resource = aws_emrserverless_application.spark.arn
      },
      {
        # Airflow (via this role) needs to hand the job-execution role to
        # EMR Serverless when starting a run — not to assume it itself.
        Sid      = "PassEMRJobExecutionRole"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = aws_iam_role.emr_job.arn
      },
    ]
  })
}

resource "aws_iam_instance_profile" "airflow_ec2" {
  name = "${var.project_name}-airflow-ec2-profile"
  role = aws_iam_role.airflow_ec2.name
}

resource "aws_instance" "airflow" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.ec2_instance_type
  key_name               = aws_key_pair.airflow.key_name
  subnet_id              = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.airflow_ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.airflow_ec2.name

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }

  # t3.small is burstable: it earns CPU credits and hard-throttles to 20%
  # baseline once they're exhausted. "unlimited" lets it burst past that
  # (billed per vCPU-hour for the overage) instead of grinding to a halt —
  # hit this exact wall running a container rebuild + a 541k-row extraction
  # back to back. No AWS-side spending cap on this; bounded instead by our
  # existing Budget alerts and the habit of pausing EC2 between sessions.
  credit_specification {
    cpu_credits = "unlimited"
  }

  tags = {
    Name = "${var.project_name}-airflow"
  }
}
