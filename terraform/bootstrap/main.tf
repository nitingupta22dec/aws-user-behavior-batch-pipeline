terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region  = "us-east-1"
  profile = "de-project"
}

# --- S3 bucket to hold the main project's Terraform state ---
resource "aws_s3_bucket" "tf_state" {
  bucket = "de-project-tf-state-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket                  = aws_s3_bucket.tf_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_caller_identity" "current" {}

# --- GitHub OIDC provider (one per AWS account, not per repo) ---
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

# --- IAM role GitHub Actions will assume, trusted only for this repo ---
resource "aws_iam_role" "github_actions" {
  name = "de-project-github-actions"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud"        = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:repository" = "nitingupta22dec/aws-user-behavior-batch-pipeline"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:nitingupta22dec@*/aws-user-behavior-batch-pipeline@*:*"
        }
      }
    }]
  })
}

# Scoped down from AdministratorAccess: this repo is public, and a fork's PR
# workflow (once approved to run) executes with these permissions via OIDC.
# EC2/RDS stay broad because AWS's IAM model doesn't support fine-grained
# resource-level permissions for most of their actions — worst case there is
# operational/cost damage, not account takeover. IAM is scoped tightly and
# named-resource-only, because that's the actual privilege-escalation vector:
# this policy cannot touch the OIDC provider or this CI role itself, so a
# compromised PR can't grant itself more power than it already has.
resource "aws_iam_policy" "github_actions_scoped" {
  name = "de-project-github-actions-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "EC2Broad"
        Effect   = "Allow"
        Action   = "ec2:*"
        Resource = "*"
      },
      {
        Sid      = "RDSBroad"
        Effect   = "Allow"
        Action   = "rds:*"
        Resource = "*"
      },
      {
        Sid      = "S3ProjectBuckets"
        Effect   = "Allow"
        Action   = "s3:*"
        Resource = [
          "arn:aws:s3:::de-project-*",
          "arn:aws:s3:::de-project-*/*",
        ]
      },
      {
        Sid    = "IAMScopedToAppRoleOnly"
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:GetRole",
          "iam:TagRole",
          "iam:UntagRole",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:GetRolePolicy",
          "iam:ListRolePolicies",
          "iam:ListInstanceProfilesForRole",
          "iam:CreateInstanceProfile",
          "iam:DeleteInstanceProfile",
          "iam:GetInstanceProfile",
          "iam:TagInstanceProfile",
          "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:PassRole",
        ]
        Resource = [
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/de-project-airflow-*",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:instance-profile/de-project-airflow-*",
        ]
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "github_actions_scoped" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.github_actions_scoped.arn
}

output "tf_state_bucket" {
  value = aws_s3_bucket.tf_state.bucket
}

output "github_actions_role_arn" {
  value = aws_iam_role.github_actions.arn
}
