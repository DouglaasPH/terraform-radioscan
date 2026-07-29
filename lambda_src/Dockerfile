# Imagem base oficial da AWS para funcoes Lambda em container (Python 3.12)
FROM public.ecr.aws/lambda/python:3.12

# Dependencias Python (tensorflow-cpu é bem menor que o tensorflow "full" com GPU)
COPY requirements.txt ${LAMBDA_TASK_ROOT}/
RUN pip install -r requirements.txt --target "${LAMBDA_TASK_ROOT}" --no-cache-dir

# Codigo da funcao
COPY app.py ${LAMBDA_TASK_ROOT}/

# Modelo treinado (coloque o modelo.h5 em lambda_src/model/ antes do build)
COPY model/modelo.h5 ${LAMBDA_TASK_ROOT}/model/modelo.h5

# Handler: arquivo app.py, funcao handler()
CMD [ "app.handler" ]
