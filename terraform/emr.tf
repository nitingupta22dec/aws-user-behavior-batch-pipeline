resource "aws_emrserverless_application" "spark" {
  name          = "${var.project_name}-spark"
  release_label = "emr-7.14.0"
  type          = "SPARK"

  auto_stop_configuration {
    enabled              = true
    idle_timeout_minutes = 15
  }

  tags = {
    Name = "${var.project_name}-spark"
  }
}

# IAM role EMR Serverless assumes to run the classification job itself —
# separate from the EC2 instance role, same least-privilege pattern.
resource "aws_iam_role" "emr_job" {
  name = "${var.project_name}-emr-job-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "emr-serverless.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "emr_job_s3" {
  name = "${var.project_name}-emr-job-s3-access"
  role = aws_iam_role.emr_job.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadRawAndScripts"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:ListBucket"]
        Resource = [
          aws_s3_bucket.raw.arn,
          "${aws_s3_bucket.raw.arn}/*",
        ]
      },
      {
        Sid      = "WriteProcessed"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject", "s3:ListBucket", "s3:DeleteObject"]
        Resource = [
          aws_s3_bucket.processed.arn,
          "${aws_s3_bucket.processed.arn}/*",
        ]
      },
    ]
  })
}

output "emr_application_id" {
  value = aws_emrserverless_application.spark.id
}

output "emr_job_role_arn" {
  value = aws_iam_role.emr_job.arn
}
