FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt \
    && opentelemetry-bootstrap -a install

COPY shopping_server.py .
COPY images/ images/

ENV PYTHONUNBUFFERED=1
ENV OTEL_PYTHON_LOGGING_AUTO_INSTRUMENTATION_ENABLED=true
ENV OTEL_SERVICE_NAME=shoppingdemo-backend
ENV OTEL_TRACES_EXPORTER=otlp
ENV OTEL_METRICS_EXPORTER=otlp
ENV OTEL_LOGS_EXPORTER=otlp
ENV OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317
ENV OTEL_EXPORTER_OTLP_PROTOCOL=grpc
ENV OTEL_METRIC_EXPORT_INTERVAL=5000

EXPOSE 5173

CMD ["sh", "-c", "opentelemetry-instrument uvicorn shopping_server:app --host 0.0.0.0 --port 5173"]
