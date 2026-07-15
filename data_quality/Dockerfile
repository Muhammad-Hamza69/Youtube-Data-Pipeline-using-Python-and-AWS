# Rebuild trigger: AWS environment fully recreated from scratch (2026-07-15).
FROM public.ecr.aws/lambda/python:3.11 AS builder

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt --target /opt/python

FROM public.ecr.aws/lambda/python:3.11

COPY --from=builder /opt/python ${LAMBDA_TASK_ROOT}
COPY dq_lambda.py ${LAMBDA_TASK_ROOT}

CMD ["dq_lambda.lambda_handler"]


