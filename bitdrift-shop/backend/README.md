# Bitdrift Shop Backend API

FastAPI server providing realistic e-commerce data for the **Bitdrift Shop** app used in the **Bitdrift 301 SDK Workshop**. Serves a catalog of 18 products with randomized browsing, search, cart management, checkout, and payment flows. Includes OpenTelemetry auto-instrumentation for traces, metrics, and structured JSON logs.

Server runs on `http://localhost:5173`.

---

## Workshop Quick Start

If you're here for the workshop, this is all you need:

```bash
./start-backend-docker.sh        # pull latest from Docker Hub and run
./start-backend-chaos-docker.sh  # same, with chaos mode enabled (fault injection)
./stop-backend-docker.sh         # stop the running container
```

No Python, no virtualenv — just Docker.

**Chaos mode** is used in workshop scenarios that test error handling and resilience — it injects random API faults (slow responses, 500 errors, payment failures) so the SDK can capture and surface them.

### Observability variant (tinyolly)

If you're running with a local OpenTelemetry collector on the `tinyolly-network` Docker network (e.g. via the tinyolly stack), use the o11y scripts instead:

```bash
./start-backend-docker-o11y.sh        # join tinyolly-network; otherwise same as above
./start-backend-chaos-docker.sh       # chaos mode; use CHAOS_MODE=1 with o11y script if needed
./stop-backend-docker.sh              # stop the running container
```

The `tinyolly-network` external network must exist before starting:

```bash
docker network create tinyolly-network
```

The standard `./start-backend-docker.sh` does **not** require this network and uses Docker's default bridge instead.
---

## API Docs

- **Swagger UI**: `http://localhost:5173/docs`
- **ReDoc**: `http://localhost:5173/redoc`

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/health` | Health check |
| GET | `/api/welcome` | Store info + promotions |
| GET | `/api/browse` | Product listing (8 random of 18) |
| GET | `/api/search?q=` | Search products by keyword |
| GET | `/api/featured` | Featured products with badges |
| GET | `/api/categories` | Category listing |
| GET | `/api/categories/{name}` | Products in a specific category |
| GET | `/api/product/{id}` | Product detail with images |
| GET | `/api/product/{id}/reviews` | Product reviews + ratings |
| GET | `/api/cart` | Get current cart contents |
| POST | `/api/cart` | Add item to cart → cart summary |
| DELETE | `/api/cart/{product_id}` | Remove item from cart |
| POST | `/api/wishlist` | Add to wishlist |
| POST | `/api/checkout/guest` | Guest checkout session |
| POST | `/api/checkout/signin` | Member checkout session |
| POST | `/api/payment/card` | Card payment → transaction ID |
| POST | `/api/payment/applepay` | Apple Pay → transaction ID |
| POST | `/api/payment/paypal` | PayPal → transaction ID |
| POST | `/api/payment/androidpay` | Android Pay → transaction ID |
| GET | `/api/confirmation/{id}` | Order confirmation details |
| GET | `/api/inventory/lookup/{item}/{session}` | Inventory lookup (cardinality demo) |

### Response Latency

Heavy endpoints have built-in artificial latency (independent of chaos mode) to create visible response time differences:

| Endpoint | Latency | Rationale |
|----------|---------|----------|
| `GET /api/product/{id}/reviews` | 400–1200ms | Simulates review aggregation query |
| `GET /api/confirmation/{id}` | 300–800ms | Simulates order assembly + recommendation engine |
| `GET /api/product/{id}` | 200–600ms | Simulates DB joins across related products, Q&A, price history |
| All other endpoints | instant | No artificial delay |

## Response Sizes by Endpoint

Endpoints are deliberately sized to create dramatic bandwidth differences visible in the Bitdrift dashboard's "request/response size by endpoint" charts:

| Endpoint | Approx. Size | Latency | What makes it large |
|----------|-------------|---------|---------------------|
| `GET /api/product/{id}/reviews` | **~330 KB** | 400–1200ms | 150 full reviews with author profiles, photos, seller responses, pros/cons |
| `GET /api/confirmation/{id}` | **~95 KB** | 300–800ms | 8-18 line items, 15 recommendations, 12 "also viewed" with preview reviews, policies |
| `GET /api/product/{id}` | **~76 KB** | 200–600ms | Related products, 30 Q&A threads, competitor comparison matrix, 90-day price history |
| `GET /api/browse` | **~8 KB** | instant | 8 enriched product cards with trending data, shipping estimates, promotions, seller info |
| `GET /api/welcome` | ~0.2 KB | instant | Store info + 2 promos |
| `POST /api/payment/*` | **~0.2 KB** | instant | Minimal: status, transaction ID, order ID, amount |

The heavy endpoints also have **artificial latency** injected server-side, so both the "response size by endpoint" and "response time by endpoint" charts show dramatic differences in the dashboard.

---

## Build and Run Locally (Docker)

For backend development — build your own image from source:

```bash
./build.sh          # build image (stevelerner/bitdrift-shop-backend:latest)
./run.sh            # run the locally built image
./docker-cleanup.sh # stop and remove the container
```

### Push to Docker Hub

```bash
./dockerhub-push.sh           # push latest
./dockerhub-push.sh v1.0.0    # tag and push version
```
---

## Docker Compose

The scripts are thin wrappers around compose files. You can also use compose directly:

**Standard (no external network required):**
```bash
docker compose up --pull always              # start (latest) — Ctrl-C to stop
docker compose down                          # remove the container

TAG=v1.0.0 docker compose up --pull always   # specific version
CHAOS_MODE=1 docker compose up --pull always # chaos mode
```

**With tinyolly observability network:**
```bash
docker compose -f docker-compose.yml -f docker-compose.o11y.yml up --pull always
docker compose -f docker-compose.yml -f docker-compose.o11y.yml down
```

`docker-compose.o11y.yml` is an override file that attaches the container to the external `tinyolly-network`, enabling communication with a local OTel collector running in that network.
---

## Run without Docker

> **Deprecated** — the `local/` scripts now just delegate to the Docker scripts above. Direct Python startup is no longer maintained.

To run without Docker, install dependencies and start the server manually:

```bash
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
python shopping_server.py

# Chaos mode:
CHAOS_MODE=1 python shopping_server.py
```

### Clean up local dev files

```bash
./cleanup.sh  # removes venv, __pycache__, .pyc files
```

---

## OpenTelemetry

When running via Docker the server automatically starts under `opentelemetry-instrument`. Set the collector endpoint via env var:

```bash
OTEL_EXPORTER_OTLP_ENDPOINT=http://your-collector:4317 docker compose up --pull always
```

Traces, metrics, and **logs** are all exported via OTLP to the configured collector. Logs are also emitted as structured JSON to stdout with `trace_id` and `span_id` fields injected when a span is active. The `opentelemetry-instrumentation-logging` package wires Python's `logging` module into the OTel SDK so every log record (including uvicorn access logs) is exported to the collector.

---
## Product Images

The server serves product images at `/images/{product_id}.png`. The 18 images are **committed to the repo** and included in the Docker image — no generation step is needed for normal use.

### Regenerating images (Pexels API)

To refresh the images with new photos from [Pexels](https://www.pexels.com/):

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install Pillow

PEXELS_API_KEY=<your-key> python generate_images.py
```

Get a free API key at https://www.pexels.com/api/. The script searches Pexels for each product, downloads the top result, center-crops to square, and resizes to 400×400. If a search fails, it falls back to a gray placeholder with the product initials.

After regenerating, rebuild the Docker image to include the new images:

```bash
./build.sh
```

## Chaos Mode

Chaos mode injects random faults into API responses for resilience testing. Faults are applied probabilistically — each request rolls the dice independently.

### Activation

**Option 1 — Docker** (recommended):

```bash
./start-backend-chaos-docker.sh
```

**Option 2 — Local startup script:**

```bash
./local/start-backend-chaos.sh
```

**Option 3 — Environment variable:**

```bash
CHAOS_MODE=1 python shopping_server.py
```

**Option 4 — Runtime toggle** (enable/disable without restart):

```bash
curl -X POST http://localhost:5173/api/chaos/enable
curl -X POST http://localhost:5173/api/chaos/disable
```

**Option 5 — Per-request** (header or query param):

```bash
curl -H "X-Chaos: on" http://localhost:5173/api/browse
curl http://localhost:5173/api/browse?chaos=1
```

### Fault Types

| Fault | Default Probability | Effect |
|-------|-------------------|--------|
| `slow_response` | 15% | 2–12 second delay |
| `http_404` | 8% | Not Found |
| `http_500` | 6% | Internal Server Error |
| `http_503` | 4% | Service Unavailable with Retry-After |
| `slow_images` | 25% | 3–8 second delay on image requests |
| `truncated_json` | 4% | Malformed JSON body |
| `empty_lists` | 7% | Arrays replaced with `[]` |
| `stale_data` | 8% | Product detail returns mutated price, zero stock, or "[DISCONTINUED]" name |
| `payment_failure` | 12% | Payment endpoints return decline/timeout error |
| `session_expiry` | 8% | 401 Unauthorized on checkout/payment |
| `rate_limiting` | 4% | 429 Too Many Requests |

### Control Endpoints

| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/chaos/enable` | Turn chaos mode on |
| POST | `/api/chaos/disable` | Turn chaos mode off |
| GET | `/api/chaos/status` | Current config and hit stats |
| POST | `/api/chaos/configure` | Update fault probabilities |
| POST | `/api/chaos/reset-stats` | Zero out hit counters |

**Example — increase payment failures to 50%**:

```bash
curl -X POST http://localhost:5173/api/chaos/configure \
  -H "Content-Type: application/json" \
  -d '{"fault_type": "payment_failure", "probability": 0.5}'
```

**Example — check stats**:

```bash
curl http://localhost:5173/api/chaos/status
```

## Cleanup

Remove generated files (venv, images, `__pycache__`):

```bash
./cleanup.sh
```
