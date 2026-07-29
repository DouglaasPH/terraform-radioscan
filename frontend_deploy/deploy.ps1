# deploy.ps1 (referencia para o frontend)
# Publica os arquivos estaticos (HTML/CSS/JS ja buildados) no bucket S3 do
# site (aws_s3_bucket.website), servido pelo CloudFront na frente.
#
# Funciona com qualquer frontend que gere uma pasta de build estatica
# (React/Vite -> "dist", Create React App -> "build", Angular -> "dist/<app>",
# site estatico puro -> a propria pasta com os .html).
#
# Pre-requisitos: AWS CLI instalado, LocalStack rodando, bucket ja criado
# (ou seja, "terraform apply" do terraform-radioscan ja rodou pelo menos uma vez).
#
# Uso:
#   .\deploy.ps1 -BuildDir "dist"
#   .\deploy.ps1 -ProjectName "radioscan" -Environment "dev" -BuildDir "build"

param(
    [string]$ProjectName = "radioscan",
    [string]$Environment = "dev",
    [string]$BuildDir = "dist",
    [string]$Region = "sa-east-1",
    [string]$Endpoint = "http://localhost:4566"
)

$ErrorActionPreference = "Stop"

$BucketName = "$ProjectName-$Environment-website"

if (-not (Test-Path $BuildDir)) {
    throw "Pasta de build '$BuildDir' nao encontrada. Rode o build do seu frontend antes (ex: npm run build) ou ajuste -BuildDir para o nome certo."
}

Write-Host "==> Publicando '$BuildDir' em s3://$BucketName ..."
aws --endpoint-url=$Endpoint s3 sync $BuildDir "s3://$BucketName" --delete --region $Region
if ($LASTEXITCODE -ne 0) { throw "aws s3 sync falhou (exit code $LASTEXITCODE)" }

Write-Host "==> Deploy concluido!"
Write-Host "==> Acesso direto pelo bucket (website endpoint): confira com 'terraform output website_bucket_name'"
Write-Host "==> Acesso via CDN: confira com 'terraform output cloudfront_domain_name'"
Write-Host ""
Write-Host "OBS: o LocalStack (Community/Student) tem suporte limitado a invalidacao"
Write-Host "de cache do CloudFront. Se voce atualizar o site e o CDN continuar"
Write-Host "servindo a versao antiga, teste acessar o bucket diretamente para"
Write-Host "confirmar se o problema e so cache."
