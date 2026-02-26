resource "aws_iam_user" "training" {
  name = "${local.env_prefix}-terraform"
  path = "/"
}

resource "aws_iam_user_policy" "training" {
  name = "${local.env_prefix}-training-policy"
  user = aws_iam_user.training.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECR"
        Effect = "Allow"
        Action = [
          "ecr:CreateRepository",
          "ecr:PutImageScanningConfiguration",
          "ecr:PutLifecyclePolicy",
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Sid    = "ECRPush"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
        Resource = "arn:aws:ecr:*:*:repository/${local.env_prefix}"
      },
      {
        Sid    = "IAM"
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:PutRolePolicy",
          "iam:GetRole",
          "iam:DeleteRolePolicy",
          "iam:DeleteRole"
        ]
        Resource = "arn:aws:iam::${local.account_id}:role/${local.env_prefix}-sagemaker-training"
      },
      {
        Sid    = "PassRole"
        Effect = "Allow"
        Action = "iam:PassRole"
        Resource = "arn:aws:iam::${local.account_id}:role/${local.env_prefix}-sagemaker-training"
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "sagemaker.amazonaws.com"
          }
        }
      },
      {
        Sid    = "S3Terraform"
        Effect = "Allow"
        Action = [
          "s3:CreateBucket",
          "s3:PutBucketVersioning",
          "s3:PutBucketPublicAccessBlock",
          "s3:GetBucketVersioning",
          "s3:GetBucketPublicAccessBlock",
          "s3:GetBucketLocation",
          "s3:PutBucketTagging"
        ]
        Resource = "arn:aws:s3:::${local.env_prefix}-training-*"
      },
      {
        Sid    = "S3SageMaker"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::sagemaker-*",
          "arn:aws:s3:::sagemaker-*/*",
          "arn:aws:s3:::${local.env_prefix}-training-*",
          "arn:aws:s3:::${local.env_prefix}-training-*/*"
        ]
      },
      {
        Sid    = "SageMaker"
        Effect = "Allow"
        Action = [
          "sagemaker:CreateTrainingJob",
          "sagemaker:DescribeTrainingJob",
          "sagemaker:ListTrainingJobs"
        ]
        Resource = "*"
      },
      {
        Sid      = "STS"
        Effect   = "Allow"
        Action   = "sts:GetCallerIdentity"
        Resource = "*"
      }
    ]
  })
}
