#!/usr/bin/env bash
# build_and_push.sh
# Equivalente ao build_and_push.ps1, para Linux/Mac/WSL.
#
# Uso:
#   ./build_and_push.sh [project_name] [tag] [region] [endpoint]
set -euo pipefail

PROJECT_NAME="${1:-radioscan}"
TAG="${2:-v1}"
REGION="${3:-sa-east-1}"
ENDPOINT="${4:-http://localhost:4566}"

REPO_NAME="${PROJECT_NAME}-image-processor"

echo "==> Descobrindo URL do repositorio ECR '${REPO_NAME}' no LocalStack..."
REPO_URL=$(aws --endpoint-url="$ENDPOINT" ecr describe-repositories \
  --repository-names "$REPO_NAME" \
  --region "$REGION" \
  --query "repositories[0].repositoryUri" \
  --output text)

if [ -z "$REPO_URL" ] || [ "$REPO_URL" = "None" ]; then
  echo "Repositorio ECR '${REPO_NAME}' nao encontrado. Rode antes: terraform apply -target=aws_ecr_repository.lambda_model" >&2
  exit 1
fi

echo "==> Repositorio: $REPO_URL"

if [ ! -f "./model/modelo.h5" ]; then
  echo "Arquivo lambda_src/model/modelo.h5 nao encontrado. Copie seu modelo treinado para essa pasta antes de continuar." >&2
  exit 1
fi

echo "==> Login no ECR (LocalStack)..."
aws --endpoint-url="$ENDPOINT" ecr get-login-password --region "$REGION" \
  | docker login --username AWS --password-stdin "${REPO_URL%%/*}"

echo "==> Build da imagem (pode demorar por causa do TensorFlow)..."
docker build -t "${REPO_URL}:${TAG}" .

echo "==> Push da imagem para o LocalStack..."
docker push "${REPO_URL}:${TAG}"

echo "==> Concluido! Imagem publicada em: ${REPO_URL}:${TAG}"
echo "==> Confirme que var.lambda_image_tag no Terraform esta igual a: ${TAG}"
echo "==> Agora rode: terraform apply"
