#!/bin/bash
set -euo pipefail

# ───────────────
# 設定
# ───────────────
AWS_REGION="ap-northeast-1"
ECR_ACCOUNT="455110051621"
SERVICE_NAME="example-prod-foobar"
CLUSTER_NAME="example-prod-foobar"

# PHPとnginxのDockerfileパス
PHP_DOCKERFILE="./infra/docker/php/Dockerfile"
NGINX_DOCKERFILE="./infra/docker/nginx/Dockerfile"

# イメージ名
PHP_IMAGE_NAME="${SERVICE_NAME}-php"
NGINX_IMAGE_NAME="${SERVICE_NAME}-nginx"

# ECRリポジトリ
PHP_ECR="${ECR_ACCOUNT}.dkr.ecr.${AWS_REGION}.amazonaws.com/${PHP_IMAGE_NAME}:latest"
NGINX_ECR="${ECR_ACCOUNT}.dkr.ecr.${AWS_REGION}.amazonaws.com/${NGINX_IMAGE_NAME}:latest"

# ───────────────
# 1. PHPイメージ build & push
# ───────────────
echo "==> Building PHP image..."
docker build -t ${PHP_IMAGE_NAME} -f ${PHP_DOCKERFILE} .

echo "==> Tagging PHP image..."
docker tag ${PHP_IMAGE_NAME}:latest ${PHP_ECR}

echo "==> Pushing PHP image to ECR..."
docker push ${PHP_ECR}

# ───────────────
# 2. nginxイメージ build & push
# ───────────────
echo "==> Building nginx image..."
docker build -t ${NGINX_IMAGE_NAME} -f ${NGINX_DOCKERFILE} .

echo "==> Tagging nginx image..."
docker tag ${NGINX_IMAGE_NAME}:latest ${NGINX_ECR}

echo "==> Pushing nginx image to ECR..."
docker push ${NGINX_ECR}

# ───────────────
# 3. ECSサービス更新
# ───────────────
echo "==> Updating ECS service for new images..."
aws ecs update-service \
  --cluster ${CLUSTER_NAME} \
  --service ${SERVICE_NAME} \
  --force-new-deployment
  --output text

echo "==> Deployment triggered. ECS will start new tasks with latest images."
