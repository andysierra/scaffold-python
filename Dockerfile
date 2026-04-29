FROM python:3.14.4-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    libjpeg-dev \
    libtiff-dev \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY /src /src

RUN useradd --create-home --shell /bin/bash appuser && chown -R appuser:appuser /app
USER appuser

ENV PYTHONUNBUFFERED=1
EXPOSE 8080
CMD ["uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8080"]