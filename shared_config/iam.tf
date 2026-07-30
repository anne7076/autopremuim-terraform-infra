# ============================================
#  EC2 INSTANCE ROLES
# ============================================
resource "aws_iam_role" "instance_role" {
  name_prefix = "ec2-role-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow"
        Action = ["sts:AssumeRole"]
        Principal = {
          Service = "ec2.amazonaws.com"
        },
      }
    ]
  })
}

resource "aws_iam_role_policy" "allow_ec2_secretmanager" {
  name_prefix = "allow-ec2-db-"
  role        = aws_iam_role.instance_role.name

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
          aws_db_instance.database.master_user_secret[0].secret_arn # pour le DDL
        ]
      }
    ]
  })
}
resource "aws_iam_role_policy" "allow_ec2_s3" {
  name_prefix = "allow-ec2-s3"
  role        = aws_iam_role.instance_role.name

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
      },
    ]
  })
}

# Allow instance to query SSM parameters with /app/* prefix
data "aws_iam_policy_document" "allow_ssm_parameters" {
  statement {
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath"
    ]
    resources = ["arn:aws:ssm:*:*:parameter/app/*"]
  }
}
resource "aws_iam_role_policy" "allow_ec2_ssm_parameters" {
  name_prefix = "allow-ec2-ssm-params-"
  role        = aws_iam_role.instance_role.name

  policy = data.aws_iam_policy_document.allow_ssm_parameters.json
}

resource "aws_iam_role_policy_attachment" "ec2_ecr_read_only" {
  role       = aws_iam_role.instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}
resource "aws_iam_role_policy_attachment" "ec2_ssm_core" {
  role       = aws_iam_role.instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
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
