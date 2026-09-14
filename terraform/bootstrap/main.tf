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
# EC2/RDS actions that CREATE a resource stay broad (the resource doesn't
# exist yet, so it has no tag to condition on). Actions that MUTATE or DELETE
# an existing resource are restricted to resources tagged Project=de-project
# — this contains blast radius to just this project's own resources and
# blocks lateral movement to anything else in the account.
#
# Caveat, stated plainly: this does NOT fully close the risk of a compromised
# CI run reconfiguring THIS project's own security group (e.g. opening RDS to
# 0.0.0.0/0) and reading the RDS password out of Terraform state (which
# necessarily holds it, in plaintext, for Terraform to function) — that
# specific resource is tagged de-project, so it's exactly the resource this
# role is meant to manage. The real backstop for that scenario is GitHub's
# required-approval gate on fork PR workflow runs (see repo Settings ->
# Actions -> General), not IAM. IAM is scoped tightly and named-resource-only
# for the actual privilege-escalation vector (IAM itself): this policy cannot
# touch the OIDC provider or this CI role, so a compromised PR can't grant
# itself more power than it already has.
resource "aws_iam_policy" "github_actions_scoped" {
  name = "de-project-github-actions-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EC2ReadAndCreate"
        Effect = "Allow"
        Action = [
          "ec2:Describe*",
          "ec2:RunInstances",
          "ec2:CreateSecurityGroup",
          "ec2:CreateKeyPair",
          "ec2:ImportKeyPair",
          "ec2:CreateVolume",
          "ec2:CreateTags",
        ]
        Resource = "*"
      },
      {
        Sid    = "EC2MutateExistingTaggedOnly"
        Effect = "Allow"
        Action = [
          "ec2:TerminateInstances",
          "ec2:StopInstances",
          "ec2:StartInstances",
          "ec2:ModifyInstanceAttribute",
          "ec2:ModifyInstanceCreditSpecification",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:AuthorizeSecurityGroupEgress",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupEgress",
          "ec2:DeleteSecurityGroup",
          "ec2:DeleteKeyPair",
          "ec2:DeleteVolume",
          "ec2:AttachVolume",
          "ec2:DetachVolume",
          "ec2:DeleteTags",
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/Project" = "de-project"
          }
        }
      },
      {
        Sid    = "RDSReadAndCreate"
        Effect = "Allow"
        Action = [
          "rds:Describe*",
          "rds:CreateDBInstance",
          "rds:AddTagsToResource",
          "rds:ListTagsForResource",
        ]
        Resource = "*"
      },
      {
        Sid    = "RDSMutateExistingTaggedOnly"
        Effect = "Allow"
        Action = [
          "rds:ModifyDBInstance",
          "rds:DeleteDBInstance",
          "rds:StopDBInstance",
          "rds:StartDBInstance",
          "rds:RemoveTagsFromResource",
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/Project" = "de-project"
          }
        }
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
          "iam:ListAttachedRolePolicies",
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
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/de-project-emr-*",
        ]
      },
      {
        Sid      = "EMRServerless"
        Effect   = "Allow"
        Action   = "emr-serverless:*"
        Resource = "*"
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
