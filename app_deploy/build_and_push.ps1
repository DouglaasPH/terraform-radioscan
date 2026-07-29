# build_and_push.ps1 (referencia para a clinic_api)
# Copie este script para a raiz do repositorio da API, junto com o Dockerfile.
#
# Pre-requisitos: mesmos da Lambda (Docker Desktop, AWS CLI, LocalStack rodando,
# repositorio ECR ja criado pelo terraform-radioscan - ele já é criado no
# primeiro "terraform apply", nao precisa de -target separado como a Lambda).
#
# Uso:
#   .\build_and_push.ps1 -ProjectName "radioscan" -Tag "v1"

param(
    [string]$ProjectName = "radioscan",
    [string]$Tag = "v1",
    [string]$Region = "sa-east-1",
    [string]$Endpoint = "http://localhost:4566"
)

$ErrorActionPreference = "Stop"

Write-Host "==> Descobrindo URL do repositorio ECR '$ProjectName' no LocalStack..."
$RepoUrl = aws --endpoint-url=$Endpoint ecr describe-repositories `
    --repository-names $ProjectName `
    --region $Region `
    --query "repositories[0].repositoryUri" `
    --output text

if ([string]::IsNullOrWhiteSpace($RepoUrl)) {
    throw "Repositorio ECR '$ProjectName' nao encontrado. Rode 'terraform apply' no projeto terraform-radioscan primeiro."
}

Write-Host "==> Repositorio: $RepoUrl"

Write-Host "==> Login no ECR (LocalStack)..."
$RegistryHost = $RepoUrl.Split("/")[0]
aws --endpoint-url=$Endpoint ecr get-login-password --region $Region | docker login --username AWS --password-stdin $RegistryHost
if ($LASTEXITCODE -ne 0) { throw "docker login falhou (exit code $LASTEXITCODE)" }

Write-Host "==> Build da imagem..."
docker build -t "${RepoUrl}:${Tag}" .
if ($LASTEXITCODE -ne 0) { throw "docker build falhou (exit code $LASTEXITCODE) - veja o erro de compilacao acima, o push NAO vai rodar" }

Write-Host "==> Push da imagem para o LocalStack..."
docker push "${RepoUrl}:${Tag}"
if ($LASTEXITCODE -ne 0) { throw "docker push falhou (exit code $LASTEXITCODE)" }

Write-Host "==> Concluido! Imagem publicada em: ${RepoUrl}:${Tag}"
Write-Host "==> No projeto terraform-radioscan, defina var.app_image_tag = `"$Tag`" e rode: terraform apply"
