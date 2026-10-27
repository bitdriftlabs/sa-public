# ── build stage: resolve and install dependencies into a venv; none of this ships except the venv ──
FROM python:3.12-slim AS build
# OpenTelemetry is NOT in the default image. Build with --build-arg WITH_OTEL=1 (tools/build.sh otel) to include it.
ARG WITH_OTEL=0
ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1
RUN python -m venv /opt/venv
ENV PATH=/opt/venv/bin:$PATH
WORKDIR /build
COPY requirements.txt requirements-otel.txt ./
RUN pip install --upgrade pip \
    && pip install -r requirements.txt \
    && if [ "$WITH_OTEL" = 1 ]; then \
         pip install -r requirements-otel.txt && opentelemetry-bootstrap -a install; \
       fi \
    # Nothing installs packages at runtime, so the installers go too, and so do the bytecode caches
    # (PYTHONDONTWRITEBYTECODE below keeps them from coming back).
    && pip uninstall -y pip setuptools wheel \
    && find /opt/venv -type d -name __pycache__ -prune -exec rm -rf {} +

# ── runtime stage ──────────────────────────────────────────────────────────────────────────────────
FROM python:3.12-slim
# The base image's package lists, apt and dpkg caches, docs and man pages are not needed to run Python
# (nothing is installed with apt here). Clearing them keeps the layer from carrying any of it.
RUN apt-get clean \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/* /var/log/apt /var/log/dpkg.log /var/log/alternatives.log \
              /usr/share/doc /usr/share/man /usr/share/info /usr/share/lintian /tmp/*

COPY --from=build /opt/venv /opt/venv
ENV PATH=/opt/venv/bin:$PATH

WORKDIR /app
COPY shopping_server.py .
COPY images/ images/

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1
# OpenTelemetry needs an image built with WITH_OTEL=1; there, OTEL_ENABLED=1 runs under opentelemetry-instrument
# and exports to the collector below. Left off, the server never tries to reach a collector.
ENV OTEL_ENABLED=0
ENV OTEL_PYTHON_LOGGING_AUTO_INSTRUMENTATION_ENABLED=true
ENV OTEL_SERVICE_NAME=shoppingdemo-backend
ENV OTEL_TRACES_EXPORTER=otlp
ENV OTEL_METRICS_EXPORTER=otlp
ENV OTEL_LOGS_EXPORTER=otlp
ENV OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317
ENV OTEL_EXPORTER_OTLP_PROTOCOL=grpc
ENV OTEL_METRIC_EXPORT_INTERVAL=5000

EXPOSE 5173

# The default image (WITH_OTEL=0) has no opentelemetry-instrument; OTEL_ENABLED=1 then warns and runs plain.
CMD ["sh", "-c", "if [ \"$OTEL_ENABLED\" = 1 ] && command -v opentelemetry-instrument >/dev/null; then exec opentelemetry-instrument uvicorn shopping_server:app --host 0.0.0.0 --port 5173; fi; if [ \"$OTEL_ENABLED\" = 1 ]; then echo 'OTEL_ENABLED=1 but this image has no OpenTelemetry (build with WITH_OTEL=1, or use the :otel tag); running without it' >&2; fi; exec uvicorn shopping_server:app --host 0.0.0.0 --port 5173"]
