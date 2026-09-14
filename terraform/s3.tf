# Global uniqueness for bucket names.
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "raw" {
  bucket        = "${var.project_name}-raw-${random_id.bucket_suffix.hex}"
  force_destroy = true # allow easy teardown for a learning project

  tags = {
    Name = "${var.project_name}-raw"
  }
}

resource "aws_s3_bucket" "processed" {
  bucket        = "${var.project_name}-processed-${random_id.bucket_suffix.hex}"
  force_destroy = true

  tags = {
    Name = "${var.project_name}-processed"
  }
}

resource "aws_s3_bucket_public_access_block" "raw" {
  bucket                  = aws_s3_bucket.raw.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "processed" {
  bucket                  = aws_s3_bucket.processed.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
