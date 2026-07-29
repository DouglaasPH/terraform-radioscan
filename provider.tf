provider "aws" {
  region = "sa-east-1"

  access_key = "mock_access_key"
  secret_key = "mock_secret_key"

  # Impede o Terraform de tentar buscar credenciais na AWS real ou no metadados (IP 169.254.169.254)
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  # Sem isso, o provider tenta endereçar buckets S3 no estilo
  # "nome-do-bucket.localhost:4566" (virtual-hosted style), que falha por DNS
  # ("no such host"). Forca o estilo "localhost:4566/nome-do-bucket".
  s3_use_path_style = true

  # Redireciona os serviços da AWS usados no diagrama para o LocalStack local.
  # No LocalStack, todos os serviços ficam atrás do mesmo edge port (4566),
  # então todos apontam para o mesmo endereço.
  endpoints {
    s3                      = "http://localhost:4566"
    iam                     = "http://localhost:4566"
    ec2                     = "http://localhost:4566"
    sts                     = "http://localhost:4566"
    ecs                     = "http://localhost:4566"
    ecr                     = "http://localhost:4566"
    elb                     = "http://localhost:4566"
    elbv2                   = "http://localhost:4566"
    rds                     = "http://localhost:4566"
    lambda                  = "http://localhost:4566"
    sns                     = "http://localhost:4566"
    sqs                     = "http://localhost:4566"
    route53                 = "http://localhost:4566"
    cloudfront               = "http://localhost:4566"
    wafv2                   = "http://localhost:4566"
    cloudwatch               = "http://localhost:4566"
    cloudwatchlogs           = "http://localhost:4566"
    applicationautoscaling   = "http://localhost:4566"
  }
}

# Provider auxiliar (mesmo endpoint do LocalStack, "região" us-east-1).
# Na AWS real, um Web ACL do WAF associado a uma distribuição CloudFront
# só pode ser criado com scope = "CLOUDFRONT" a partir da região us-east-1.
# No LocalStack essa restrição não é aplicada (é tudo o mesmo processo local),
# mas mantemos o alias para o código ficar compatível se um dia vocês migrarem
# para a AWS de verdade.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  access_key = "mock_access_key"
  secret_key = "mock_secret_key"

  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    wafv2 = "http://localhost:4566"
  }
}
