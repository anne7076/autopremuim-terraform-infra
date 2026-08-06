# ============================================
#  EC2 INSTANCE ROLE & POLICY ATTACHMENTS
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

resource "aws_iam_role_policy_attachment" "ec2_secrets_ssm" {
  role       = aws_iam_role.instance_role.name
  policy_arn = module.common_config.secrets_ssm_policy_arn
}

resource "aws_iam_role_policy_attachment" "ec2_s3" {
  role       = aws_iam_role.instance_role.name
  policy_arn = module.common_config.s3_policy_arn
}

resource "aws_iam_role_policy_attachment" "ec2_ecr_read_only" {
  role       = aws_iam_role.instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "ec2_ssm_core" {
  role       = aws_iam_role.instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
