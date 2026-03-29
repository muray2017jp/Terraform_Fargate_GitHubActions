#!/bin/bash

# エラー発生時に即座に停止し、未定義変数をエラーとする
set -euo pipefail

# ===============================
# 1. パスと基本変数の設定
# ===============================
# スクリプトの実行場所を基準にパスを固定
SCRIPT_DIR=$(cd $(dirname $0); pwd)
cd "${SCRIPT_DIR}"

AWS_REGION="ap-northeast-1"
ACCOUNT_ID="455110051621"
CLUSTER_NAME="example-prod-foobar"
SERVICE_NAME="example-prod-foobar"

# 各ディレクトリの定義
APP_DIR="${SCRIPT_DIR}/laravel-fargate-app"
INFRA_DIR="${SCRIPT_DIR}/laravel-fargate-infra"
PROD_DIR="${INFRA_DIR}/envs/prod"

# 共通ファイルの参照元
REAL_PROVIDER="${PROD_DIR}/provider.tf"
REAL_SHARED_LOCALS="${PROD_DIR}/shared_locals.tf"

# ECRリポジトリ設定
TAG="latest"
PHP_REPO="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/example-prod-foobar-php"
NGINX_REPO="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/example-prod-foobar-nginx"

# ===============================
# 2. Terraform Apply 関数
# ===============================
apply_tf () {
  TARGET_DIR=$1
  echo ""
  echo "############################################################"
  echo " Processing: ${TARGET_DIR}"
  echo "############################################################"

  if [ ! -d "${TARGET_DIR}" ]; then
    echo "SKIP: Directory ${TARGET_DIR} not found."
    return
  fi

  cd "${TARGET_DIR}"
  
  # 既存のキャッシュをクリアしてクリーンな状態で実行
  rm -rf .terraform .terraform.lock.hcl
  
  # バックアップファイルの退避
  mkdir -p .temp_backup
  find . -maxdepth 1 -type f \( -name "*.bak" -o -name "*.bak2" -o -name "*.org" -o -name "*.txt" \) -exec mv {} .temp_backup/ \; 2>/dev/null || true

  # provider等の共通ファイルをコピー
  rm -f provider.tf shared_locals.tf
  cp "${REAL_PROVIDER}" provider.tf
  cp "${REAL_SHARED_LOCALS}" shared_locals.tf

  # Terraform実行
  terraform init -upgrade -reconfigure
  
  if ls *.tf >/dev/null 2>&1; then
    terraform apply -auto-approve
  fi

  # バックアップの復元
  if [ -d ".temp_backup" ]; then
    mv .temp_backup/* . 2>/dev/null || true
    rm -rf .temp_backup
  fi
  cd "${SCRIPT_DIR}"
}

# ===============================
# 3. インフラ・デプロイ順序
# ===============================
echo "Starting Infrastructure Deployment..."

# ネットワークからアプリ層まで順番に反映
apply_tf "${PROD_DIR}/network/main"
apply_tf "${PROD_DIR}/log/alb"
apply_tf "${PROD_DIR}/log/app_foobar"
apply_tf "${PROD_DIR}/log/db_foobar"
apply_tf "${PROD_DIR}/db/foobar"
apply_tf "${PROD_DIR}/cache/foobar"
apply_tf "${PROD_DIR}/routing/appfoobar_link"
apply_tf "${PROD_DIR}/app/foobar"

# ===============================
# 4. Docker Build & Push
# ===============================
echo "Logging in to ECR..."
aws ecr get-login-password --region ${AWS_REGION} | \
docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

echo "Building and Pushing Docker Images..."

# PHPイメージ
docker build -t "${PHP_REPO}:${TAG}" -f "${APP_DIR}/infra/docker/php/Dockerfile" "${APP_DIR}"
docker push "${PHP_REPO}:${TAG}"

# Nginxイメージ
docker build -t "${NGINX_REPO}:${TAG}" -f "${APP_DIR}/infra/docker/nginx/Dockerfile" "${APP_DIR}"
docker push "${NGINX_REPO}:${TAG}"

# ===============================
# 5. ECS Service Update & Migration
# ===============================
echo "Updating ECS service (Force New Deployment)..."
aws ecs update-service \
  --cluster "${CLUSTER_NAME}" \
  --service "${SERVICE_NAME}" \
  --force-new-deployment \
  --region "${AWS_REGION}" > /dev/null

echo "Waiting for the new task to stabilize (Healthy status in ALB)..."
# 新しいコンテナが起動し、ロードバランサーのチェックが通るまで待機（重要）
aws ecs wait services-stable \
  --cluster "${CLUSTER_NAME}" \
  --services "${SERVICE_NAME}" \
  --region "${AWS_REGION}"

# 稼働中の最新タスクARNを取得
TASK_ARN=$(aws ecs list-tasks \
  --cluster "${CLUSTER_NAME}" \
  --service-name "${SERVICE_NAME}" \
  --desired-status RUNNING \
  --query 'taskArns[0]' \
  --output text \
  --region "${AWS_REGION}")

if [ "${TASK_ARN}" != "None" ] && [ "${TASK_ARN}" != "" ]; then
    echo "Running: php artisan migrate --force on Task: ${TASK_ARN}"
    
    # コンテナ内でマイグレーションを実行
    aws ecs execute-command --cluster "${CLUSTER_NAME}" \
        --task "${TASK_ARN}" \
        --container php \
        --interactive \
        --command "php artisan migrate --force" \
        --region "${AWS_REGION}"
        
    echo "Migration completed successfully."
else
    echo "ERROR: No running tasks found. Skipping migration."
    exit 1
fi

echo "All deployment steps completed successfully! 🚀"