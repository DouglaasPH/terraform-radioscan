variable "vpc_cidr_block" {
  description = "Bloco CIDR da minha VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "project_name" {
  description = "Nome do projeto"
  type        = string
  default     = "radioscan"
}

variable "environment" {
  description = "Ambiente (dev, staging, prod)"
  type        = string
  default     = "dev"
}

# Networking
variable "availability_zones" {
  description = "AZs para as subnets. Corrigido para sa-east-1 (São Paulo), igual ao diagrama e ao backend/provider."
  type        = list(string)
  default     = ["sa-east-1a", "sa-east-1c"]
}

variable "public_subnet_cidrs" {
  description = "CIDRs das subnets públicas"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDRs das subnets privadas"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.20.0/24"]
}

# ECS / Container
variable "container_port" {
  description = "Porta exposta pelo container"
  type        = number
  default     = 80
}

variable "task_cpu" {
  description = "CPU units para a task"
  type        = string
  default     = "256"
}

variable "task_memory" {
  description = "Memória em MiB para a task"
  type        = string
  default     = "512"
}

variable "desired_count" {
  description = "Número desejado de tasks rodando"
  type        = number
  default     = 2
}

variable "min_capacity" {
  description = "Mínimo de tasks no auto scaling"
  type        = number
  default     = 1
}

variable "max_capacity" {
  description = "Máximo de tasks no auto scaling"
  type        = number
  default     = 4
}

# Frontend - S3 / CloudFront / WAF / Route53
variable "domain_name" {
  description = "Domínio usado na Route53 Hosted Zone. Pode ser fictício (ex: radioscan.local), já que é simulação no LocalStack."
  type        = string
  default     = "radioscan.local"
}

# RDS
variable "db_name" {
  description = "Nome do banco de dados"
  type        = string
  default     = "radioscandb"
}

variable "db_username" {
  description = "Usuário master do RDS"
  type        = string
  default     = "radioscan_admin"
}

variable "db_password" {
  description = "Senha do RDS. Se deixar null, uma senha aleatória é gerada automaticamente. Prefira sobrescrever via terraform.tfvars ou variável de ambiente TF_VAR_db_password."
  type        = string
  default     = null
  sensitive   = true
}

variable "db_engine_version" {
  description = "Versão do PostgreSQL"
  type        = string
  default     = "15"
}

variable "db_instance_class" {
  description = "Classe da instância RDS"
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "Armazenamento alocado (GB)"
  type        = number
  default     = 20
}

# Lambda (imagem de container com TensorFlow)
variable "lambda_image_tag" {
  description = "Tag da imagem publicada no ECR para a Lambda. Incremente (ex: v2, v3) sempre que reconstruir a imagem (novo codigo ou novo modelo.h5), para o Terraform detectar a mudanca."
  type        = string
  default     = "v1"
}

variable "lambda_timeout" {
  description = "Timeout da Lambda (segundos). TensorFlow costuma precisar de mais tempo, principalmente no cold start."
  type        = number
  default     = 120
}

variable "lambda_memory_size" {
  description = "Memoria (MB) da Lambda. TensorFlow precisa de bastante memoria; mais memoria tambem significa mais CPU alocada."
  type        = number
  default     = 3008
}

variable "app_image_tag" {
  description = "Tag da imagem da API Java publicada no ECR (aws_ecr_repository.this). Incremente (v2, v3...) a cada novo deploy para o Terraform detectar a mudança."
  type        = string
  default     = "v1"
}

variable "sqs_max_receive_count" {
  description = "Quantas vezes uma mensagem pode ser reprocessada (ex: falha no modelo, RDS fora do ar) antes de ir para a Dead Letter Queue"
  type        = number
  default     = 3
}

# Integração com a tabela x_ray_report (entidade JPA XRayReport da API Java)
variable "xray_report_table" {
  description = "Nome da tabela onde a Lambda grava o resultado (mapeada pela entidade JPA XRayReport)"
  type        = string
  default     = "x_ray_report"
}

variable "xray_report_status_completed" {
  description = "Valor de processingStatus gravado quando a IA termina com sucesso (equivalente a ProcessingStatus.PROCESSED_BY_IA no enum Java)"
  type        = number
  default     = 2
}

# Segredos da API (JWT / OAuth2 Google). SEM valor default de propósito -
# defina via variável de ambiente TF_VAR_xxx ou um terraform.tfvars local
# (adicione terraform.tfvars ao .gitignore - NUNCA versione segredos reais).
variable "jwt_secret_key" {
  description = "Chave secreta usada para assinar os JWT (JWT_SECRET_KEY)"
  type        = string
  sensitive   = true
}

variable "jwt_expiration_in_minutes" {
  description = "Tempo de expiracao do JWT em minutos (JWT_EXPIRATION_IN_MINUTES)"
  type        = number
  default     = 5
}

variable "oauth2_google_client_id" {
  description = "Client ID do OAuth2 do Google (OAUTH2_GOOGLE_CLIENT_ID)"
  type        = string
  sensitive   = true
}

variable "oauth2_google_client_secret" {
  description = "Client Secret do OAuth2 do Google (OAUTH2_GOOGLE_CLIENT_SECRET)"
  type        = string
  sensitive   = true
}
