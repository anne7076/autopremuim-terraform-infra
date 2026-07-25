resource "aws_iam_instance_profile" "ec2_profile" {
  name_prefix = "ec2-iam-profile-"
  role        = aws_iam_role.ec2_role.id
}
resource "aws_iam_role" "ec2_role" {
  name_prefix = "ec2-role-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow"
        Action = ["sts:assumeRole"]
        Principal = {
          Service = "ec2.amazonaws.com"
        },
      }
    ]
  })
}

resource "aws_iam_role_policy" "allow_ec2_secretmanager" {
  name_prefix = "allow-ec2-db-"
  role        = aws_iam_role.ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "secretsmanager:GetSecretValue"
        ],
        Resource = aws_secretsmanager_secret.db_secrets.arn
      }
    ]
  })
}

resource "aws_iam_role_policy" "allow_ec2_s3" {
  name_prefix = "allow-ec2-s3"
  role        = aws_iam_role.ec2_role.id

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
