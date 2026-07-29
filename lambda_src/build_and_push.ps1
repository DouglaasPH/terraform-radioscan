# build_and_push.ps1
# Builda a imagem Docker da Lambda (TensorFlow + modelo.h5) e envia para o
# repositorio ECR do LocalStack.
#
# Pre-requisitos:
#   - Docker Desktop rodando
#   - AWS CLI instalado (aws --version)
#   - LocalStack rodando em http://localhost:4566
#   - lambda_src/model/modelo.h5 presente
#   - O repositorio ECR ja deve existir (rode antes:
#       terraform apply -target=aws_ecr_repository.lambda_model)
#
# Uso:
#   .\build_and_push.ps1 -ProjectName "radioscan" -Environment "dev" -Tag "v1"

param(
    [string]$ProjectName = "radioscan",
    [string]$Tag = "v1",
    [string]$Region = "sa-east-1",
    [string]$Endpoint = "http://localhost:4566"
)

$ErrorActionPreference = "Stop"

$RepoName = "$ProjectName-image-processor"

Write-Host "==> Descobrindo URL do repositorio ECR '$RepoName' no LocalStack..."
$RepoUrl = aws --endpoint-url=$Endpoint ecr describe-repositories `
    --repository-names $RepoName `
    --region $Region `
    --query "repositories[0].repositoryUri" `
    --output text

if ([string]::IsNullOrWhiteSpace($RepoUrl)) {
    throw "Repositorio ECR '$RepoName' nao encontrado. Rode antes: terraform apply -target=aws_ecr_repository.lambda_model"
}

Write-Host "==> Repositorio: $RepoUrl"

if (-not (Test-Path ".\model\modelo.h5")) {
    throw "Arquivo lambda_src\model\modelo.h5 nao encontrado. Copie seu modelo treinado para essa pasta antes de continuar."
}

Write-Host "==> Login no ECR (LocalStack)..."
$RegistryHost = $RepoUrl.Split("/")[0]
aws --endpoint-url=$Endpoint ecr get-login-password --region $Region | docker login --username AWS --password-stdin $RegistryHost
if ($LASTEXITCODE -ne 0) { throw "docker login falhou (exit code $LASTEXITCODE)" }

Write-Host "==> Build da imagem (isso pode demorar alguns minutos por causa do TensorFlow)..."
docker build -t "${RepoUrl}:${Tag}" .
if ($LASTEXITCODE -ne 0) { throw "docker build falhou (exit code $LASTEXITCODE) - o push NAO vai rodar" }

Write-Host "==> Push da imagem para o LocalStack..."
docker push "${RepoUrl}:${Tag}"
if ($LASTEXITCODE -ne 0) { throw "docker push falhou (exit code $LASTEXITCODE)" }

Write-Host "==> Concluido! Imagem publicada em: ${RepoUrl}:${Tag}"
Write-Host "==> Confirme que var.lambda_image_tag no Terraform esta igual a: $Tag"
Write-Host "==> Agora rode: terraform apply"
