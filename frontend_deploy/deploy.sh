#!/usr/bin/env bash
# deploy.sh (referencia para o frontend) - equivalente ao deploy.ps1
#
# Uso:
#   ./deploy.sh [project_name] [environment] [build_dir] [region] [endpoint]
set -euo pipefail

PROJECT_NAME="${1:-radioscan}"
ENVIRONMENT="${2:-dev}"
BUILD_DIR="${3:-dist}"
REGION="${4:-sa-east-1}"
ENDPOINT="${5:-http://localhost:4566}"

BUCKET_NAME="${PROJECT_NAME}-${ENVIRONMENT}-website"

if [ ! -d "$BUILD_DIR" ]; then
  echo "Pasta de build '$BUILD_DIR' nao encontrada. Rode o build do frontend antes (ex: npm run build) ou passe o nome certo como 3o argumento." >&2
  exit 1
fi

echo "==> Publicando '$BUILD_DIR' em s3://${BUCKET_NAME} ..."
aws --endpoint-url="$ENDPOINT" s3 sync "$BUILD_DIR" "s3://${BUCKET_NAME}" --delete --region "$REGION"

echo "==> Deploy concluido!"
echo "==> Acesso direto pelo bucket: terraform output website_bucket_name"
echo "==> Acesso via CDN: terraform output cloudfront_domain_name"
