# radioscan — Infra no LocalStack (Terraform)

Infraestrutura completa da aplicação **radioscan**, simulando AWS via **LocalStack**
(plano Student), cobrindo: site estático (S3 + CloudFront + WAF + Route53),
API Java em ECS/Fargate, banco RDS PostgreSQL, e o pipeline de análise de
raio-X por IA (S3 → SNS → SQS → Lambda com TensorFlow → RDS).

## Sumário

1. [Arquitetura](#arquitetura)
2. [Pré-requisitos](#pré-requisitos)
3. [Passo a passo: subir a infraestrutura](#passo-a-passo-subir-a-infraestrutura)
4. [Publicando a Lambda de IA](#publicando-a-lambda-de-ia)
5. [Publicando a API Java (clinic-api)](#publicando-a-api-java-clinic-api)
6. [Publicando o Frontend](#publicando-o-frontend)
7. [Testando tudo ponta a ponta](#testando-tudo-ponta-a-ponta)
8. [Atualizando depois de mudanças](#atualizando-depois-de-mudanças)
9. [Destruindo tudo](#destruindo-tudo)
10. [Pontos de atenção / simplificações assumidas](#pontos-de-atenção--simplificações-assumidas)

---

## Arquitetura

| Camada | Arquivo Terraform | Recursos principais |
|---|---|---|
| Rede | `main.tf` | VPC, subnets públicas/privadas, IGW, NAT, route tables |
| Frontend | `frontend.tf` | `aws_s3_bucket.website`, `aws_cloudfront_distribution.cdn`, `aws_wafv2_web_acl.cdn`, `aws_route53_zone.this` |
| Backend (API) | `main.tf` | ALB, ECS Cluster/Service/Task (Fargate), ECR, IAM roles |
| Banco | `database.tf` | `aws_db_instance.this` (PostgreSQL, subnets privadas) |
| Pipeline de imagens | `messaging-images.tf` | `aws_s3_bucket.images`, `aws_sns_topic.image_upload`, `aws_sqs_queue.image_processing` (+ DLQ), `aws_lambda_function.image_processor`, `aws_ecr_repository.lambda_model` |

Fluxo do pipeline de imagens (100% automático depois do upload):

```
1. Cliente pede URL pré-assinada -> StorageGateway.generatePresignedUploadUrl()  (API)
2. Cliente faz PUT direto no S3 usando essa URL
3. S3 dispara evento ObjectCreated -> SNS -> SQS          (automático, via Terraform)
4. SQS -> Lambda (TensorFlow + modelo.h5) -> roda o modelo
5. Lambda faz UPDATE x_ray_report SET ai_result, processing_status WHERE s3_key = ...
```

---

## Pré-requisitos

- **Docker Desktop** rodando
- **Terraform** (`terraform -v`)
- **AWS CLI** (`aws --version`)
- **awslocal**: `pip install --break-system-packages awscli-local`
- Um **token do plano Student do LocalStack** (vinculado ao GitHub Student
  Developer Pack) — dá acesso ao catálogo completo de serviços emulados
  (CloudFront, WAF, Route53, RDS, Lambda, SNS, SQS, ECS/Fargate, ECR, ALB),
  necessário porque desde 23/03/2026 o LocalStack exige uma imagem única
  autenticada por `LOCALSTACK_AUTH_TOKEN` (não existe mais o modo Community
  "sem login")

Opcional, mas necessário se você for publicar a API e o frontend:

- **Java 25** + o próprio `mvnw` do projeto `clinic-api` (não precisa instalar
  Maven à parte)
- **Node/npm** (ou o que seu frontend usar) para gerar o build estático

---

## Passo a passo: subir a infraestrutura

### 1. Subir o LocalStack

```powershell
$env:LOCALSTACK_AUTH_TOKEN="<seu token do plano student>"

docker run --rm -it `
  -p 4566:4566 `
  -e LOCALSTACK_AUTH_TOKEN=$env:LOCALSTACK_AUTH_TOKEN `
  -v /var/run/docker.sock:/var/run/docker.sock `
  localstack/localstack
```

Deixe essa janela aberta. Em outro terminal, confirme que subiu:

```powershell
awslocal sts get-caller-identity
```

> O `-v /var/run/docker.sock:/var/run/docker.sock` é necessário para o
> LocalStack conseguir rodar containers de verdade (ECS/Fargate).

### 2. Extrair o projeto

```powershell
cd C:\Users\dougl\terraform-radioscan
```

### 3. Colocar o modelo treinado

Copie seu `modelo.h5` para:

```
lambda_src\model\modelo.h5
```

### 4. Criar o bucket do backend remoto (state)

O `backend.tf` aponta para um bucket S3 que precisa existir *antes* do
`terraform init` (problema do "ovo e a galinha"):

```powershell
awslocal s3 mb s3://radioscan-tfstate-local
```

### 5. Inicializar

```powershell
terraform init
```

### 6. Criar primeiro só o ECR da Lambda

A Lambda referencia uma imagem Docker que ainda não existe — se você rodar
`apply` completo agora, essa parte falha:

```powershell
terraform apply -target=aws_ecr_repository.lambda_model
```

### 7. Buildar e publicar a imagem da Lambda

Ver detalhes na seção [Publicando a Lambda de IA](#publicando-a-lambda-de-ia)
abaixo. Resumo:

```powershell
cd lambda_src
.\build_and_push.ps1 -ProjectName "radioscan" -Tag "v1"
cd ..
```

### 8. Aplicar o resto da infraestrutura

```powershell
terraform plan
terraform apply
```

Confirme com `yes`. Isso cria VPC, ALB, ECS/Fargate, ECR do app, S3 (site +
imagens), CloudFront, WAF, Route53, RDS, SNS, SQS (+ DLQ) e a Lambda.

Se quiser definir a senha do RDS manualmente em vez de deixar gerar aleatória:

```powershell
$env:TF_VAR_db_password = "uma-senha-forte"
```

### 9. Conferir os outputs

```powershell
terraform output
```

Você vai ver `alb_dns_name`, `cloudfront_domain_name`, `images_bucket_name`,
`website_bucket_name`, `rds_endpoint`, `sns_topic_arn`, `sqs_queue_url`,
`sqs_dlq_url`, `lambda_ecr_repository_url`, entre outros.

Neste ponto a **infraestrutura** está de pé, mas o ECS ainda está rodando o
placeholder (`nginx`) até você publicar a API de verdade — próximas seções.

---

## Publicando a Lambda de IA

A Lambda `image_processor` roda o modelo de classificação (COVID /
Lung_Opacity / Normal / Viral Pneumonia), adaptado do seu app Streamlit
original. Como o TensorFlow não cabe no limite de pacote `.zip` da Lambda
(250MB descompactado), ela roda como **Lambda em imagem de container
Docker** (limite de 10GB), publicada no ECR.

O que a Lambda faz (`lambda_src/app.py`):
1. Recebe da fila SQS o evento do S3 (embrulhado num envelope SNS).
2. Baixa a imagem do S3 usando o bucket/key do próprio evento.
3. Roda o mesmo pré-processamento/inferência do `arquivo.py` original
   (resize 224x224, normalização, `SafeDense` para compatibilidade do `.h5`).
4. Faz `UPDATE x_ray_report SET ai_result = ..., processing_status = 2 WHERE s3_key = <chave>`
   (`2` = `ProcessingStatus.PROCESSED_BY_IA`). `ai_result` fica no formato
   `"COVID 95,55%"`.

> **Importante**: o registro é casado por `s3_key` — é essencial que a
> `s3Key` gravada em `x_ray_report` na hora de gerar a URL pré-assinada seja
> **exatamente igual** à key usada no upload real, senão o `UPDATE` não acha
> a linha (a Lambda loga um aviso nesse caso, mas não falha).

Se der erro (imagem corrompida, RDS fora do ar etc.), a Lambda **não altera**
`processing_status` — o enum `ProcessingStatus` não tem um código de "falha",
então mexer nisso poderia confundir a etapa de validação do médico. A
mensagem é reentregue pelo SQS e cai na DLQ depois de
`var.sqs_max_receive_count` tentativas (padrão: 3).

### Passos

1. **Modelo treinado** em `lambda_src/model/modelo.h5` (passo 3 acima).
2. **ECR já criado** (passo 6 acima).
3. **Build e push:**

   ```powershell
   cd lambda_src
   .\build_and_push.ps1 -ProjectName "radioscan" -Tag "v1"
   cd ..
   ```

   (Linux/Mac/WSL: `./lambda_src/build_and_push.sh radioscan v1`)

4. **Aplique:**

   ```powershell
   terraform apply
   ```

Sempre que alterar `app.py`, `requirements.txt` ou trocar o `modelo.h5`,
**incremente `var.lambda_image_tag`** (ex: `v2`) tanto no build (`-Tag "v2"`)
quanto no Terraform (`variables.tf` ou `-var="lambda_image_tag=v2"`), repita
o passo 3 e rode `terraform apply` de novo.

---

## Publicando a API Java (clinic-api)

O `main.tf` já aponta a task definition do ECS para o ECR do projeto
(`aws_ecr_repository.this`) em vez do placeholder `nginx:latest`, e já injeta
no container as variáveis de ambiente que a aplicação espera — os nomes batem
com o `.env`/`.env.example` reais do projeto (a `springboot3-dotenv` lê `.env`
localmente; em produção/LocalStack essas mesmas chaves vêm como env var do
container, sem precisar de `.env` nenhum). A API só precisa gerar a URL
pré-assinada; ela não fala com SQS/SNS em nenhum momento (isso é automático
via evento do S3).

| Env var | Origem no Terraform | Observação |
|---|---|---|
| `SERVER_PORT` | `var.container_port` | porta HTTP |
| `DB_HOST` | `aws_db_instance.this.address` | endpoint do RDS |
| `DB_PORT` | `aws_db_instance.this.port` | porta do RDS |
| `DB_NAME` | `var.db_name` | |
| `DB_USER` | `var.db_username` | |
| `DB_PASSWORD` | `local.db_password` | gerada automaticamente ou `var.db_password` |
| `JWT_SECRET_KEY` | `var.jwt_secret_key` | **obrigatório**, sem default |
| `JWT_EXPIRATION_IN_MINUTES` | `var.jwt_expiration_in_minutes` | default: `5` |
| `OAUTH2_GOOGLE_CLIENT_ID` | `var.oauth2_google_client_id` | **obrigatório**, sem default |
| `OAUTH2_GOOGLE_CLIENT_SECRET` | `var.oauth2_google_client_secret` | **obrigatório**, sem default |
| `AWS_S3_BUCKET_NAME` | `aws_s3_bucket.images.bucket` | usado por `StorageGateway` |
| `AWS_REGION` | fixo `"sa-east-1"` | usado por `S3Config` |
| `AWS_ENDPOINT` | fixo `"http://localhost:4566"` | usado por `S3Config.s3Presigner()` |

> **`jwt_secret_key`, `oauth2_google_client_id` e `oauth2_google_client_secret`
> não têm valor default de propósito** — são segredos reais (o mesmo do seu
> `.env`) e não devem ficar hardcoded em `variables.tf` nem versionados no
> Git. Antes do `terraform apply`, defina via variável de ambiente:
>
> ```powershell
> $env:TF_VAR_jwt_secret_key = "MinhaChaveSuperSecretaE..."
> $env:TF_VAR_oauth2_google_client_id = "783372180414-....apps.googleusercontent.com"
> $env:TF_VAR_oauth2_google_client_secret = "GOCSPX-...."
> ```
>
> ou crie um `terraform.tfvars` **local** (adicione ao `.gitignore`!) com:
>
> ```hcl
> jwt_secret_key              = "MinhaChaveSuperSecretaE..."
> oauth2_google_client_id     = "783372180414-....apps.googleusercontent.com"
> oauth2_google_client_secret = "GOCSPX-...."
> ```
>
> Sem isso, o `terraform plan`/`apply` para e pede o valor interativamente.

> Como o `S3Config.java` usa credenciais **estáticas hardcoded** (`"test"/"test"`,
> as credenciais convencionais do LocalStack), não é preciso passar
> `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` — eles não seriam lidos mesmo.

> **`AWS_ENDPOINT = http://localhost:4566`**: precisa ser alcançável por quem
> **usa** a URL pré-assinada depois (o navegador do paciente, Postman etc.),
> não pelo container em si — por isso `localhost:4566` (a máquina onde o
> LocalStack está rodando), e não `host.docker.internal`.

### Passos

Os arquivos de referência ficam em `app_deploy/` neste projeto — **copie-os
para a raiz do repositório da API** (`clinic-api`, mesmo nível do
`pom.xml`/`mvnw`):

1. Copie `app_deploy/Dockerfile.reference` → `clinic-api/Dockerfile`
   (já ajustado para usar o Maven Wrapper `mvnw` e Java 25, conforme o `pom.xml`).
2. Copie `app_deploy/dockerignore.reference` → `clinic-api/.dockerignore`
   (evita copiar `target/`, `.env`, `.git` etc. para dentro da imagem).
3. Copie `app_deploy/build_and_push.ps1` → raiz de `clinic-api`.
4. **Confira/substitua** `S3Config.java` pelo conteúdo de
   `app_deploy/S3Config.java.reference` (versão sem o bean `SqsClient`, já
   que a API não fala mais com o SQS diretamente).
5. Rode (dentro da pasta `clinic-api`):

   ```powershell
   .\build_and_push.ps1 -ProjectName "radioscan" -Tag "v1"
   ```

6. De volta na pasta `terraform-radioscan`:

   ```powershell
   terraform apply
   ```

   (o `aws_ecs_service` faz um novo deployment automaticamente quando a task
   definition muda)

7. Acompanhe os logs se algo não subir:

   ```powershell
   awslocal logs tail /ecs/radioscan --follow
   ```

8. Teste pela URL do ALB:

   ```powershell
   terraform output alb_dns_name
   curl http://<alb_dns_name>/algum-endpoint
   ```

Sempre que redeployar, repita o passo 5 com uma tag nova (`v2`, `v3`...) e
atualize `var.app_image_tag` em `variables.tf` (mesmo esquema da Lambda).

---

## Publicando o Frontend

O site estático fica no bucket `aws_s3_bucket.website`, servido publicamente
via CloudFront (com WAF na frente). O Terraform já cria o bucket, configura
hospedagem estática nele e sobe a distribuição CloudFront — falta só
**publicar os arquivos** depois de gerar o build do seu frontend.

Os arquivos de referência ficam em `frontend_deploy/` neste projeto:

1. Gere o build estático do seu frontend normalmente (ex: `npm run build`,
   `npm run dist`, ou o comando equivalente do seu framework). Anote o nome
   da pasta gerada (`dist`, `build`, etc.).
2. Copie `frontend_deploy/deploy.ps1` (ou `.sh`) para a raiz do repositório
   do frontend.
3. Rode, apontando para a pasta de build:

   ```powershell
   .\deploy.ps1 -BuildDir "dist"
   ```

   (Linux/Mac/WSL: `./deploy.sh radioscan dev dist`)

   Isso faz um `aws s3 sync` da pasta de build para o bucket
   `radioscan-dev-website`, apagando do bucket o que não existir mais localmente
   (`--delete`).

4. Acesse pelo bucket diretamente (mais simples para testar) ou pelo
   CloudFront:

   ```powershell
   terraform output website_bucket_name
   terraform output cloudfront_domain_name
   ```

> O LocalStack tem suporte limitado a invalidação de cache do CloudFront. Se
> você atualizar o site e o CDN continuar servindo a versão antiga, teste
> acessar o bucket diretamente para confirmar se é só cache — nesse caso,
> aguardar um pouco ou recriar a distribuição costuma resolver em ambiente
> local.

> Se o seu frontend chama a API diretamente do navegador (ex: para pedir a
> URL pré-assinada), aponte a base URL da API no seu frontend para o
> `alb_dns_name` (`terraform output alb_dns_name`) antes de gerar o build.

Sempre que atualizar o frontend, repita o passo 3 (o `deploy.ps1` sempre
sincroniza tudo de novo).

---

## Testando tudo ponta a ponta

```powershell
# 1. Simular um upload direto no bucket (pulando a URL pré-assinada, só para
#    testar se o gatilho S3 -> SNS -> SQS -> Lambda está funcionando)
awslocal s3 cp caminho\para\raiox.png s3://<images_bucket_name>/teste.png

# 2. Acompanhar a Lambda processando
awslocal logs tail /aws/lambda/radioscan-image-processor --follow

# 3. Ver se caiu alguma mensagem na DLQ (sinal de erro persistente)
awslocal sqs receive-message --queue-url <sqs_dlq_url>
```

Se aparecer `AVISO: nenhum registro em 'x_ray_report' com s3_key='teste.png'`
nos logs da Lambda, é esperado nesse teste manual (não existe uma linha na
tabela com essa key ainda) — isso só bate certo de verdade quando o fluxo
completo passa pela API e pelo frontend.

Para testar o fluxo completo de verdade: acesse o site pelo
`cloudfront_domain_name` ou `website_bucket_name`, faça login/agende uma
consulta, suba um raio-X pela tela do frontend, e acompanhe os logs da
Lambda + a coluna `ai_result` na tabela `x_ray_report` (via `psql` no
`rds_endpoint`, por exemplo).

---

## Atualizando depois de mudanças

| O que mudou | O que fazer |
|---|---|
| Infra (`.tf`) | `terraform apply` |
| `app.py` / `modelo.h5` da Lambda | rebuild com nova tag (`build_and_push.ps1 -Tag vN`) + atualizar `var.lambda_image_tag` + `terraform apply` |
| Código da API | rebuild com nova tag (`build_and_push.ps1 -Tag vN`) + atualizar `var.app_image_tag` + `terraform apply` |
| Frontend | `deploy.ps1` de novo (sem precisar de `terraform apply`) |

---

## Destruindo tudo

```powershell
terraform destroy
```

---

## Pontos de atenção / simplificações assumidas

- **Task Role do ECS não é usada de fato hoje**: o `S3Config.java` usa
  credenciais estáticas (`"test"/"test"`) em vez de assumir a
  `aws_iam_role.ecs_task` via credentials provider chain. A role/policy
  continuam no Terraform como caminho de migração para AWS real (bastaria
  trocar para `DefaultCredentialsProvider` no código).
- **WAF + CloudFront**: na AWS real, um WebACL com `scope = "CLOUDFRONT"` só
  pode ser criado a partir da região `us-east-1`. Criei um `provider` alias
  (`aws.us_east_1`) apontando para o mesmo endpoint do LocalStack só por
  portabilidade — no LocalStack essa regra não é imposta.
- **Lambda em VPC**: a função fica nas subnets privadas para poder alcançar
  o RDS.
- **Dead Letter Queue**: a fila `image_processing` tem uma DLQ
  (`image_processing_dlq`) associada. Se uma mensagem falhar
  `var.sqs_max_receive_count` vezes seguidas (padrão: 3), ela vai para a DLQ,
  onde fica retida por 14 dias para investigação manual.
- **Senha do banco na Lambda**: por simplicidade, a senha do RDS é passada
  direto como variável de ambiente (`DB_PASSWORD`). Para produção real, o
  ideal seria usar o Secrets Manager (também emulado pelo LocalStack) em vez
  de expor a senha em texto simples nas env vars.
- **Route53**: como é tudo local, usei um domínio fictício (`var.domain_name`,
  default `radioscan.local`). Não há resolução DNS real de fora do LocalStack —
  na prática você acessa a app pelo `alb_dns_name` (backend) e pelo
  `cloudfront_domain_name`/`website_bucket_name` (frontend) diretamente.
- **RDS engine**: o LocalStack não roda um Postgres "de verdade" da mesma
  forma que a AWS — internamente ele geralmente sobe um container Postgres
  real e expõe endpoint/porta emulados, então `psql` no `rds_endpoint` deve
  funcionar para testes.
- **`s3_use_path_style = true`** no `provider.tf` é obrigatório — sem isso, o
  Terraform tenta endereçar buckets no estilo virtual-hosted
  (`bucket.localhost:4566`), que falha por DNS.
