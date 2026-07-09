FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY shopping_server.py .
COPY images/ images/

ENV PYTHONUNBUFFERED=1
ENV DD_SERVICE=shoppingdemo-backend
ENV DD_ENV=demo
ENV DD_LOGS_INJECTION=true
ENV DD_RUNTIME_METRICS_ENABLED=true
ENV DD_AGENT_HOST=dd-agent
ENV DD_TRACE_AGENT_PORT=8126
ENV DD_DOGSTATSD_HOST=dd-agent

EXPOSE 5173

CMD ["sh", "-c", "ddtrace-run uvicorn shopping_server:app --host 0.0.0.0 --port 5173"]
