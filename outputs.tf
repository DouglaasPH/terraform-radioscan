# VPC
output "vpc_id" {
  description = "VPC Id"
  value       = aws_vpc.this.id
}

# Subnets
output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = aws_subnet.private[*].id
}

# ALB
output "alb_dns_name" {
  description = "ALB DNS name – use to access the application"
  value       = aws_lb.this.dns_name
}

# ECR
output "ecr_repository_url" {
  description = "ECR repository URL"
  value       = aws_ecr_repository.this.repository_url
}

# ECS
output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.this.name
}

output "ecs_service_name" {
  description = "ECS service name"
  value       = aws_ecs_service.this.name
}

# Frontend
output "website_bucket_name" {
  description = "Bucket S3 do site estatico (frontend)"
  value       = aws_s3_bucket.website.bucket
}

output "cloudfront_domain_name" {
  description = "Dominio da distribuicao CloudFront"
  value       = aws_cloudfront_distribution.cdn.domain_name
}

output "waf_web_acl_arn" {
  description = "ARN do Web ACL do WAF associado ao CloudFront"
  value       = aws_wafv2_web_acl.cdn.arn
}

output "route53_zone_id" {
  description = "ID da Hosted Zone criada na Route53"
  value       = aws_route53_zone.this.zone_id
}

output "route53_name_servers" {
  description = "Name servers da Hosted Zone"
  value       = aws_route53_zone.this.name_servers
}

# Pipeline de imagens
output "images_bucket_name" {
  description = "Bucket S3 usado para upload de imagens via URL pre-assinada"
  value       = aws_s3_bucket.images.bucket
}

output "sns_topic_arn" {
  description = "ARN do tópico SNS de notificação de upload de imagens"
  value       = aws_sns_topic.image_upload.arn
}

output "sqs_queue_url" {
  description = "URL da fila SQS de processamento de imagens"
  value       = aws_sqs_queue.image_processing.id
}

output "sqs_dlq_url" {
  description = "URL da Dead Letter Queue - mensagens que falharam repetidas vezes caem aqui"
  value       = aws_sqs_queue.image_processing_dlq.id
}

output "lambda_function_name" {
  description = "Nome da funcao Lambda de processamento de imagens"
  value       = aws_lambda_function.image_processor.function_name
}

output "lambda_ecr_repository_url" {
  description = "URL do repositorio ECR onde a imagem Docker da Lambda deve ser publicada (ver lambda_src/build_and_push.ps1)"
  value       = aws_ecr_repository.lambda_model.repository_url
}

# RDS
output "rds_endpoint" {
  description = "Endpoint (host:porta) do RDS PostgreSQL"
  value       = aws_db_instance.this.endpoint
}

output "rds_database_name" {
  description = "Nome do banco de dados no RDS"
  value       = aws_db_instance.this.db_name
}

output "rds_username" {
  description = "Usuário master do RDS"
  value       = var.db_username
}

output "rds_password" {
  description = "Senha do RDS (sensível - use 'terraform output -raw rds_password' para ver o valor puro)"
  value       = local.db_password
  sensitive   = true
}
