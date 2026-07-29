import json
import os
from urllib.parse import unquote_plus

import boto3
import numpy as np
import psycopg2
import tensorflow as tf
from psycopg2 import sql

# ------------------------------------------------------------------
# Configuracao
# ------------------------------------------------------------------

MODEL_PATH = os.path.join(os.path.dirname(__file__), "model", "modelo.h5")
CLASS_NAMES = ["COVID", "Lung_Opacity", "Normal", "Viral Pneumonia"]

# Tabela/colunas mapeadas pela entidade JPA XRayReport (@Table("x_ray_report")).
DB_TABLE = os.environ.get("DB_TABLE", "x_ray_report")

# ProcessingStatus.PROCESSED_BY_IA (ver models/entities/enums/ProcessingStatus.java).
# O enum NAO tem um status de "falha" - por isso, se der erro, a Lambda nao
# atualiza o status (fica em AWAITING_AI) e deixa a mensagem ser reentregue
# pelo SQS ate cair na DLQ.
STATUS_COMPLETED = int(os.environ.get("STATUS_COMPLETED", "2"))

# Quando executada dentro do LocalStack, a Lambda recebe automaticamente a
# variavel de ambiente AWS_ENDPOINT_URL apontando para o gateway do LocalStack.
s3 = boto3.client("s3", endpoint_url=os.environ.get("AWS_ENDPOINT_URL"))

# Cache do modelo fora do handler: em invocacoes "quentes" (mesmo container
# reaproveitado), o modelo nao precisa ser recarregado do disco toda vez.
_modelo = None


class SafeDense(tf.keras.layers.Dense):
    """Mesmo workaround usado no app Streamlit original, para compatibilidade
    de versao do Keras ao carregar o .h5."""

    def __init__(self, *args, **kwargs):
        kwargs.pop("quantization_config", None)
        super().__init__(*args, **kwargs)


def _carregar_modelo():
    global _modelo
    if _modelo is None:
        print("Carregando modelo.h5 (cold start)...")
        _modelo = tf.keras.models.load_model(
            MODEL_PATH,
            custom_objects={"Dense": SafeDense},
            compile=False,
        )
    return _modelo


def _get_connection():
    return psycopg2.connect(
        host=os.environ["DB_HOST"],
        port=os.environ.get("DB_PORT", "5432"),
        dbname=os.environ["DB_NAME"],
        user=os.environ["DB_USER"],
        password=os.environ["DB_PASSWORD"],
        connect_timeout=10,
    )


def _predict(image_bytes):
    modelo = _carregar_modelo()

    # Mesmo pre-processamento do app Streamlit original
    img_tensor = tf.io.decode_image(image_bytes, channels=3, expand_animations=False)
    img_resized = tf.image.resize(
        img_tensor,
        [224, 224],
        method=tf.image.ResizeMethod.BILINEAR,
        antialias=True,
    )
    img_normalized = tf.cast(img_resized, tf.float32) / 255.0
    img_batch = tf.expand_dims(img_normalized, axis=0).numpy()

    raw_predictions = modelo.predict(img_batch, verbose=0)
    idx = int(np.argmax(raw_predictions, axis=-1)[0])

    classe = CLASS_NAMES[idx]
    confianca = float(raw_predictions[0][idx] * 100)

    return classe, confianca


def _formatar_ai_result(classe, confianca):
    # Ex: "COVID 95,55%" (2 casas decimais, virgula como separador, sem espaco antes do %)
    confianca_str = f"{confianca:.2f}".replace(".", ",")
    return f"{classe} {confianca_str}%"


def _atualizar_ai_result(s3_key, ai_result):
    query = sql.SQL(
        "UPDATE {table} SET ai_result = %s, processing_status = %s WHERE s3_key = %s"
    ).format(table=sql.Identifier(DB_TABLE))

    conn = _get_connection()
    try:
        with conn.cursor() as cur:
            cur.execute(query, (ai_result, STATUS_COMPLETED, s3_key))
            linhas_afetadas = cur.rowcount
        conn.commit()

        if linhas_afetadas == 0:
            print(f"AVISO: nenhum registro em '{DB_TABLE}' com s3_key='{s3_key}'")
    finally:
        conn.close()


def _processar_objeto_s3(bucket, key):
    print(f"Processando s3://{bucket}/{key}")

    obj = s3.get_object(Bucket=bucket, Key=key)
    image_bytes = obj["Body"].read()

    classe, confianca = _predict(image_bytes)
    ai_result = _formatar_ai_result(classe, confianca)

    _atualizar_ai_result(key, ai_result)

    print(f"[{key}] ai_result='{ai_result}' status={STATUS_COMPLETED}")


def handler(event, context):
    """
    Fluxo: S3 (ObjectCreated) -> SNS -> SQS -> Lambda.

    Cada 'record' e uma mensagem SQS. O corpo (body) e o envelope de
    notificacao do SNS, e dentro dele (campo "Message") esta o evento
    original do S3, disparado automaticamente quando um objeto e criado no
    bucket de imagens (configurado via aws_s3_bucket_notification).

    Se o processamento de uma mensagem falhar, a excecao e propagada (nao
    capturada aqui de proposito): o SQS marca a mensagem como nao processada
    e a reentrega ate var.sqs_max_receive_count vezes antes de cair na DLQ,
    sem sujar o processing_status do registro (o enum ProcessingStatus nao
    tem um valor de "falha").
    """
    for record in event.get("Records", []):
        sqs_body = json.loads(record["body"])
        sns_message = json.loads(sqs_body["Message"]) if "Message" in sqs_body else sqs_body

        for s3_record in sns_message.get("Records", []):
            bucket = s3_record["s3"]["bucket"]["name"]
            key = unquote_plus(s3_record["s3"]["object"]["key"])
            _processar_objeto_s3(bucket, key)

    return {"statusCode": 200, "body": "ok"}
