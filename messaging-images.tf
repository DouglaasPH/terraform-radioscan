# ================================================================
# PIPELINE DE IMAGENS: S3 (upload via URL pre-assinada) -> SNS -> SQS -> Lambda -> RDS
#
# O upload em si e feito pelo CLIENTE diretamente no S3, usando a URL
# pre-assinada gerada pela API (StorageGateway.generatePresignedUploadUrl).
# A partir dai, o disparo do pipeline e 100% automatico: o proprio S3 avisa
# via evento (ObjectCreated) -> SNS -> SQS -> Lambda, sem a API precisar
# publicar nada manualmente.
# ================================================================

resource "aws_s3_bucket" "images" {
  bucket        = "${var.project_name}-${var.environment}-images"
  force_destroy = true

  tags = {
    Name = "${var.project_name}-images-bucket"
  }
}

# Necessario para permitir upload direto do browser via URL pre-assinada
resource "aws_s3_bucket_cors_configuration" "images" {
  bucket = aws_s3_bucket.images.id

  cors_rule {
    allowed_methods = ["PUT", "POST", "GET"]
    allowed_origins = ["*"]
    allowed_headers = ["*"]
  }
}

resource "aws_sns_topic" "image_upload" {
  name = "${var.project_name}-image-upload"
}

data "aws_iam_policy_document" "sns_topic_policy" {
  statement {
    effect  = "Allow"
    actions = ["sns:Publish"]

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }

    resources = [aws_sns_topic.image_upload.arn]

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.images.arn]
    }
  }
}

resource "aws_sns_topic_policy" "image_upload" {
  arn    = aws_sns_topic.image_upload.arn
  policy = data.aws_iam_policy_document.sns_topic_policy.json
}

# S3 event notification -> SNS. Isso e o que dispara o pipeline automaticamente
# assim que o cliente termina o upload via URL pre-assinada.
resource "aws_s3_bucket_notification" "images" {
  bucket = aws_s3_bucket.images.id

  topic {
    topic_arn = aws_sns_topic.image_upload.arn
    events    = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_sns_topic_policy.image_upload]
}

resource "aws_sqs_queue" "image_processing_dlq" {
  name                      = "${var.project_name}-image-processing-dlq"
  message_retention_seconds = 1209600 # 14 dias - tempo maximo para investigar mensagens com falha

  tags = {
    Name = "${var.project_name}-image-processing-dlq"
  }
}

resource "aws_sqs_queue" "image_processing" {
  name                       = "${var.project_name}-image-processing"
  visibility_timeout_seconds = 60

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.image_processing_dlq.arn
    maxReceiveCount      = var.sqs_max_receive_count
  })

  tags = {
    Name = "${var.project_name}-image-processing"
  }
}

# Restringe a DLQ a receber redirecionamentos apenas da fila principal
resource "aws_sqs_queue_redrive_allow_policy" "image_processing_dlq" {
  queue_url = aws_sqs_queue.image_processing_dlq.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.image_processing.arn]
  })
}

# Permite que o SNS entregue mensagens na fila SQS
data "aws_iam_policy_document" "sqs_queue_policy" {
  statement {
    effect  = "Allow"
    actions = ["sqs:SendMessage"]

    principals {
      type        = "Service"
      identifiers = ["sns.amazonaws.com"]
    }

    resources = [aws_sqs_queue.image_processing.arn]

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_sns_topic.image_upload.arn]
    }
  }
}

resource "aws_sqs_queue_policy" "image_processing" {
  queue_url = aws_sqs_queue.image_processing.id
  policy    = data.aws_iam_policy_document.sqs_queue_policy.json
}

resource "aws_sns_topic_subscription" "image_upload_to_sqs" {
  topic_arn = aws_sns_topic.image_upload.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.image_processing.arn
}

# --- Lambda: consome a fila SQS e grava o resultado no RDS ---

resource "aws_security_group" "lambda" {
  name        = "${var.project_name}-lambda-sg"
  description = "Security group da Lambda de processamento de imagens"
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "${var.project_name}-lambda-sg"
  }
}

resource "aws_vpc_security_group_egress_rule" "lambda_all" {
  security_group_id = aws_security_group.lambda.id
  description       = "Saida para qualquer destino"
  ip_protocol        = "-1"
  cidr_ipv4          = "0.0.0.0/0"
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_exec" {
  name               = "${var.project_name}-lambda-exec"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = {
    Name = "${var.project_name}-lambda-exec"
  }
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

data "aws_iam_policy_document" "lambda_inline" {
  statement {
    effect = "Allow"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
    ]
    resources = [aws_sqs_queue.image_processing.arn]
  }

  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.images.arn}/*"]
  }
}

resource "aws_iam_role_policy" "lambda_inline" {
  name   = "${var.project_name}-lambda-inline"
  role   = aws_iam_role.lambda_exec.id
  policy = data.aws_iam_policy_document.lambda_inline.json
}

# ECR - repositorio para a imagem de container da Lambda (TensorFlow + modelo.h5).
# TensorFlow nao cabe no limite de pacote .zip da Lambda (250MB descompactado),
# entao esta funcao roda como "package_type = Image" (limite de 10GB).
resource "aws_ecr_repository" "lambda_model" {
  name                 = "${var.project_name}-image-processor"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  tags = {
    Name = "${var.project_name}-lambda-model-ecr"
  }
}

# IMPORTANTE: o Terraform NAO builda/pusha a imagem Docker sozinho.
# Fluxo (ver README.md):
#   1) terraform apply -target=aws_ecr_repository.lambda_model
#   2) rodar lambda_src/build_and_push.ps1 (ou .sh) para buildar e enviar a imagem
#   3) terraform apply (completo) -> cria/atualiza a Lambda com a imagem publicada
#
# var.lambda_image_tag deve ser incrementada (ex: "v2") toda vez que voce
# reconstruir a imagem (novo app.py ou novo modelo.h5), para o Terraform
# perceber que a imagem mudou e atualizar a funcao.
resource "aws_lambda_function" "image_processor" {
  function_name = "${var.project_name}-image-processor"
  role          = aws_iam_role.lambda_exec.arn
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.lambda_model.repository_url}:${var.lambda_image_tag}"

  timeout     = var.lambda_timeout
  memory_size = var.lambda_memory_size

  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      DB_HOST          = aws_db_instance.this.address
      DB_PORT          = tostring(aws_db_instance.this.port)
      DB_NAME          = var.db_name
      DB_USER          = var.db_username
      DB_PASSWORD      = local.db_password
      DB_TABLE         = var.xray_report_table
      STATUS_COMPLETED = tostring(var.xray_report_status_completed)
    }
  }

  tags = {
    Name = "${var.project_name}-image-processor"
  }
}

resource "aws_lambda_event_source_mapping" "sqs_to_lambda" {
  event_source_arn = aws_sqs_queue.image_processing.arn
  function_name    = aws_lambda_function.image_processor.arn
  batch_size       = 1
  enabled          = true
}
