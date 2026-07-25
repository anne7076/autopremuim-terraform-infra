#!/bin/bash
# =========================================================================
# AWS EC2 User Data Script - Provisioning & Deployment Docker
# Target OS: Amazon Linux 2023
# =========================================================================

# 1. Update system packages
echo "Updating system packages..."
dnf update -y

# 2. Install Docker and Git
echo "Installing Docker, Git, and AWS CLI..."
dnf install -y docker git aws-cli

# 3. Start Docker service and enable it at boot
echo "Starting Docker service..."
systemctl start docker
systemctl enable docker

# 4. Add the default EC2 user to the docker group
# Allows executing docker commands without sudo
usermod -aG docker ec2-user

# 5. Define production environment variables
# Customize these values before launching the instance or use AWS SSM Parameter Store
export AWS_REGION="eu-west-3"
export AWS_SECRET_ID="vitrine-db-credentials"
export S3_BUCKET_NAME="vitrine-voiture-assets"
export NEXT_PUBLIC_SUPABASE_URL="https://your-project.supabase.co"
export NEXT_PUBLIC_SUPABASE_ANON_KEY="your-anon-key"

# =========================================================================
# CHOOSE ONE OF THE DEPLOYMENT METHODS BELOW (Uncomment the one you want)
# =========================================================================

# -------------------------------------------------------------------------
# METHOD A: Pulling pre-built image from AWS ECR (Recommended for Production)
# Prevents high CPU/RAM usage on small EC2 instances during build.
# Note: Requires attaching an IAM Instance Role to the EC2 with ECR Pull permissions.
# -------------------------------------------------------------------------
# export AWS_ACCOUNT_ID="123456789012"
# export REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
# export IMAGE_NAME="vitrine-app"
#
# echo "Logging into AWS ECR..."
# aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${REGISTRY}
#
# echo "Pulling the latest image from ECR..."
# docker pull ${REGISTRY}/${IMAGE_NAME}:latest
#
# echo "Stopping and removing existing container..."
# docker stop vitrine-voiture || true
# docker rm vitrine-voiture || true
#
# echo "Starting the container..."
# docker run -d \
#   --name vitrine-voiture \
#   --restart always \
#   -p 80:3000 \
#   -e AWS_REGION="${AWS_REGION}" \
#   -e AWS_SECRET_ID="${AWS_SECRET_ID}" \
#   -e S3_BUCKET_NAME="${S3_BUCKET_NAME}" \
#   -e NEXT_PUBLIC_SUPABASE_URL="${NEXT_PUBLIC_SUPABASE_URL}" \
#   -e NEXT_PUBLIC_SUPABASE_ANON_KEY="${NEXT_PUBLIC_SUPABASE_ANON_KEY}" \
#   ${REGISTRY}/${IMAGE_NAME}:latest

# -------------------------------------------------------------------------
# METHOD B: Clone repository and build image directly on the EC2
# Simple to start.
# Note: Requires the EC2 SSH public key to be registered on Github/Gitlab.
# -------------------------------------------------------------------------
# export GIT_REPO_URL="git@github.com:your-username/vitrine-voiture.git"
# export APP_DIR="/home/ec2-user/vitrine-voiture"
#
# echo "Cloning the repository..."
# runuser -l ec2-user -c "git clone ${GIT_REPO_URL} ${APP_DIR}"
#
# cd ${APP_DIR}
#
# echo "Building Docker image local to EC2..."
# docker build -t vitrine-app .
#
# echo "Stopping and removing existing container..."
# docker stop vitrine-voiture || true
# docker rm vitrine-voiture || true
#
# echo "Starting the container..."
# docker run -d \
#   --name vitrine-voiture \
#   --restart always \
#   -p 80:3000 \
#   -e AWS_REGION="${AWS_REGION}" \
#   -e AWS_SECRET_ID="${AWS_SECRET_ID}" \
#   -e S3_BUCKET_NAME="${S3_BUCKET_NAME}" \
#   -e NEXT_PUBLIC_SUPABASE_URL="${NEXT_PUBLIC_SUPABASE_URL}" \
#   -e NEXT_PUBLIC_SUPABASE_ANON_KEY="${NEXT_PUBLIC_SUPABASE_ANON_KEY}" \
#   vitrine-app
