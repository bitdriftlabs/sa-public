# Switch to B3 Propagation and Zipkin (Optional)

> **Zipkin ↔ ClickStack are mutually exclusive** in `otelcol-config-extras.yml` — it only holds one exporter config at a time. This section switches from ClickStack ([README: steps 1-2](README.md#quick-start)) to Zipkin.

The bitdrift SDK is configured remotely to emit **B3 multi-header** trace context (`X-B3-TraceId`, `X-B3-SpanId`, `X-B3-Sampled`). The compose override makes every backend service propagate those headers, and Zipkin provides a visual trace viewer.

Copy the B3 override file from this repo to your `opentelemetry-demo` clone root:

```bash
cp /path/to/bitdrift-shop-opentelemetry/docker-compose.b3-propagation.yaml /path/to/opentelemetry-demo/
```

This adds a Zipkin container on port 9411, joined to the `opentelemetry-demo` network, and sets `OTEL_PROPAGATORS=b3multi,baggage` on all backend services that support it.

> **Note on `recommendation`:** The Python-based `recommendation` service requires the `opentelemetry-propagator-b3` package which is not installed in the OTel Demo image. It is intentionally excluded from the B3 override and continues to use W3C propagation. This does not affect the core shopping flow or Zipkin traces.

Add the Zipkin exporter to `src/otel-collector/otelcol-config-extras.yml` in your `opentelemetry-demo` clone (create the file if it doesn't exist):

```yaml
exporters:
  zipkin:
    endpoint: http://zipkin:9411/api/v2/spans

service:
  pipelines:
    traces:
      exporters: [debug, span_metrics, zipkin]
    metrics:
      receivers: [docker_stats, http_check/frontend-proxy, host_metrics, nginx, otlp, redis, span_metrics]
      exporters: [debug]
    logs:
      exporters: [debug]
```

Restart the backend with the B3 override layered on top:

Make sure Colima is running first (see [README: Prerequisites](README.md#prerequisites-macos) — `colima start` is a no-op if it's already up):

```bash
colima start
ENVOY_PORT=8081 docker compose \
  -f compose.yaml \
  -f docker-compose.b3-propagation.yaml \
  up \
  --scale load-generator=0 \
  --force-recreate \
  --remove-orphans \
  --detach
```

Zipkin starts on `http://localhost:9411`.

> **Note:** Always use `--force-recreate` when switching between compose configurations (stock ↔ B3). Without it, containers may keep stale environment variables from a previous run (e.g. a `recommendation` container that still has old propagator settings), which can block `frontend-proxy` from starting.

To view traces: open **http://localhost:9411**, tap **Sim 10** in the app, then click **Run Query** in Zipkin — traces appear within a few seconds. Click any trace to see the full waterfall across OTel Demo microservices, with B3 trace/span IDs matching what bitdrift recorded on the mobile side.

**bitdrift backend config** (to deep-link trace IDs from bitdrift into Zipkin):

```yaml
frontend_features:
  tracing_features:
    trace_id_deep_link_url_template: http://localhost:9411/zipkin/traces/{traceId}
  views_ui_enabled: true
runtime_set:
  runtimes:
  - matcher:
      always: true
    runtime:
      values:
        client_config.trace.propagation_mode:
          string_value: b3-multi
```
