FROM python:3.11-slim

# envsubst (gettext-base) for rendering profiles.yml.template at container start
RUN apt-get update && apt-get install -y --no-install-recommends gettext-base \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /dbt

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY dbt_project.yml packages.yml ./
COPY profiles/ profiles/
COPY macros/ macros/
COPY models/ models/
COPY tests/ tests/
COPY entrypoint.sh .
RUN chmod +x entrypoint.sh

ENTRYPOINT ["./entrypoint.sh"]
