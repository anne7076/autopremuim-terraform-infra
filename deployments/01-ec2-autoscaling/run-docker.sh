#!/bin/bash
set -euo pipefail

# Rediriger tous les logs vers un fichier pour le débogage
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

# =========================================================================
# AWS EC2 User Data Script - Provisioning & Préparation Déploiement
# Target OS: Amazon Linux 2023
# =========================================================================

echo "Updating system packages..."
dnf update -y

echo "Installing Docker, AWS CLI, and jq..."
dnf install -y docker aws-cli jq

echo "Starting Docker service..."
systemctl enable --now docker

echo "Allows executing docker commands without sudo..."
usermod -aG docker ec2-user

# Variables injectées dynamiquement par Terraform
export AWS_REGION="${aws_region}"
export AWS_ACCOUNT_ID="${aws_account_id}"
export AWS_SECRET_ID="${aws_secret_id}"
export IMAGE_NAME="${image_name}"
export APPLICATION_PORT="${application_port}"

# Récupération dynamique des configurations depuis AWS SSM Parameter Store
echo "Fetching parameters from AWS SSM Parameter Store..."
export SUPABASE_URL=$(aws ssm get-parameter --name "/app/supabase/url" --query "Parameter.Value" --output text --region "$${AWS_REGION}")
export SUPABASE_PUBLISHABLE_KEY=$(aws ssm get-parameter --name "/app/supabase/anon_key" --with-decryption --query "Parameter.Value" --output text --region "$${AWS_REGION}")
export APP_URL=$(aws ssm get-parameter --name "/app/public_url" --query "Parameter.Value" --output text --region "$${AWS_REGION}")
export S3_BUCKET_NAME=$(aws ssm get-parameter --name "/app/bucket_name" --query "Parameter.Value" --output text --region "$${AWS_REGION}")

export REGISTRY="$${AWS_ACCOUNT_ID}.dkr.ecr.$${AWS_REGION}.amazonaws.com"

echo "Logging into AWS ECR..."
aws ecr get-login-password --region "$${AWS_REGION}" | docker login --username AWS --password-stdin "$${REGISTRY}"

# -------------------------------------------------------------------------
# Démarrage de l'application
# -------------------------------------------------------------------------
echo "Pulling the latest image from ECR..."
if docker pull "$${REGISTRY}/$${IMAGE_NAME}:latest"; then
  echo "Stopping and removing existing container..."
  docker stop vitrine-voiture || true
  docker rm vitrine-voiture || true

  echo "Starting the container..."
  docker run -d \
    --name vitrine-voiture \
    --restart always \
    -p "$${APPLICATION_PORT}:3000" \
    -e AWS_REGION="$${AWS_REGION}" \
    -e AWS_SECRET_ID="$${AWS_SECRET_ID}" \
    -e S3_BUCKET_NAME="$${S3_BUCKET_NAME}" \
    -e SUPABASE_URL="$${SUPABASE_URL}" \
    -e SUPABASE_PUBLISHABLE_KEY="$${SUPABASE_PUBLISHABLE_KEY}" \
    -e APP_URL="$${APP_URL}" \
    "$${REGISTRY}/$${IMAGE_NAME}:latest"
else
  echo "⚠️ Warning: Latest image not found in ECR (this is expected on first bootstrap). Container startup skipped."
fi

# -------------------------------------------------------------------------
# Création du script de migration appelé par GitHub Actions via SSM
# -------------------------------------------------------------------------
echo "Creating helper migration script run-migration.sh..."
cat << 'EOF' > /home/ec2-user/run-migration.sh
#!/bin/bash
set -euo pipefail

export AWS_REGION="${aws_region}"
export AWS_ACCOUNT_ID="${aws_account_id}"
export AWS_SECRET_ID="${aws_secret_id}"
export MASTER_SECRET_ID="${master_secret_id}"
export IMAGE_NAME="${image_name}"
export REGISTRY="$${AWS_ACCOUNT_ID}.dkr.ecr.$${AWS_REGION}.amazonaws.com"

echo "Logging into AWS ECR..."
aws ecr get-login-password --region "$${AWS_REGION}" | docker login --username AWS --password-stdin "$${REGISTRY}"

echo "Pulling latest Docker image for migration..."
docker pull "$${REGISTRY}/$${IMAGE_NAME}:latest"

echo "Fetching master DB credentials for migrations..."
MASTER_CREDS=$(aws secretsmanager get-secret-value \
  --secret-id "$${MASTER_SECRET_ID}" \
  --query "SecretString" --output text --region "$${AWS_REGION}")
MASTER_USER=$(echo "$MASTER_CREDS" | jq -r .username)
MASTER_PASS=$(echo "$MASTER_CREDS" | jq -r .password)

APP_CREDS=$(aws secretsmanager get-secret-value \
  --secret-id "$${AWS_SECRET_ID}" \
  --query "SecretString" --output text --region "$${AWS_REGION}")
DB_HOST=$(echo "$APP_CREDS" | jq -r .host)
DB_NAME=$(echo "$APP_CREDS" | jq -r .dbname)
APP_USER=$(echo "$APP_CREDS" | jq -r .username)
APP_PASS=$(echo "$APP_CREDS" | jq -r .password)

echo "Running DB migrations..."
docker run --rm \
  -e DB_HOST="$DB_HOST" \
  -e DB_USER="$MASTER_USER" \
  -e DB_PASSWORD="$MASTER_PASS" \
  -e DB_NAME="$DB_NAME" \
  -e APP_DB_USER="$APP_USER" \
  -e APP_DB_PASS="$APP_PASS" \
  -e NODE_ENV=production \
  "$${REGISTRY}/$${IMAGE_NAME}:latest" \
  node /app/scripts/migrate.js

echo "✅ DB migration finished successfully."
EOF

chmod +x /home/ec2-user/run-migration.sh
chown ec2-user:ec2-user /home/ec2-user/run-migration.sh