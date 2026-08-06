# ============================================
#  REUSABLE STANDALONE POLICIES
# ============================================

resource "aws_iam_policy" "secrets_ssm_policy" {
  name_prefix = "app-secrets-ssm-"
  description = "Allows reading application database credentials from Secrets Manager and SSM parameters"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "secretsmanager:GetSecretValue"
        ],
        Resource = [
          aws_secretsmanager_secret.db_secrets.arn,
          aws_db_instance.database.master_user_secret[0].secret_arn
        ]
      },
      {
        Effect = "Allow",
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ],
        Resource = ["arn:aws:ssm:*:*:parameter/app/*"]
      }
    ]
  })
}

resource "aws_iam_policy" "s3_policy" {
  name_prefix = "app-s3-access-"
  description = "Allows reading and writing objects in the application S3 bucket"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject"
        ],
        Resource = ["${aws_s3_bucket.app_bucket.arn}/*"]
      }
    ]
  })
}

# ============================================
#  GitHub ODIC Configuration
# ============================================

# Le module génère le rôle avec les bonnes conditions OIDC
module "github_actions_role" {
  source      = "terraform-aws-modules/iam/aws//modules/iam-github-oidc-role"
  version     = "~> 5.0"
  name_prefix = "github-actions-role"

  # Restriction stricte au dépôt concerné
  subjects = ["repo:anne7076/automobile-vitrine:*"]
}

#  GITHUB <-> ECR CONFIGURATION
data "aws_iam_policy_document" "ecr_push" {
  statement {
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken" # Nécessaire pour faire "docker login"
    ]
    resources = ["*"] # GetAuthorizationToken ne supporte pas la restriction par ressource
  }

  statement {
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:GetRepositoryPolicy",
      "ecr:DescribeRepositories",
      "ecr:ListImages",
      "ecr:DescribeImages",
      "ecr:BatchGetImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage"
    ]
    # On limite les actions uniquement à ce repo ECR précis
    resources = [aws_ecr_repository.docker_image_repo.arn]
  }
}
resource "aws_iam_role_policy" "ecr_push_policy" {
  name_prefix = "PushToECRPolicy-"
  role        = module.github_actions_role.name
  policy      = data.aws_iam_policy_document.ecr_push.json
}

# GITHUB <-> ECS DEPLOYMENT & SECRETS CONFIGURATION
data "aws_iam_policy_document" "github_ecs_deploy" {
  statement {
    effect = "Allow"
    actions = [
      "ecs:DescribeServices",
      "ecs:UpdateService",
      "ecs:RunTask",
      "ecs:DescribeTasks",
      "logs:GetLogEvents",
      "logs:DescribeLogStreams"
    ]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "iam:PassRole"
    ]
    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/ecs-task-role-*",
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/ecs-execution-role-*"
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:ListSecrets"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "github_ecs_deploy_policy" {
  name_prefix = "ECSDeployPolicy-"
  role        = module.github_actions_role.name
  policy      = data.aws_iam_policy_document.github_ecs_deploy.json
}
