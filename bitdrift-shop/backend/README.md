# Bitdrift Shop Backend API

FastAPI server providing realistic e-commerce data for the **Bitdrift Shop** apps.
Serves a catalog of 18 products with randomized browsing, search, cart, checkout,
and payment flows, plus a chaos mode for fault injection.

Runs on `http://localhost:5173`. Shared by every app in this repo —
[android/](../android/), [ios/](../ios/), [reactnative/](../reactnative/).

---

## Quick start

```bash
./start-backend-docker.sh         # normal
./start-backend-chaos-docker.sh   # with fault injection
```

That's it. No Python, no virtualenv — just Docker. Both run in the foreground, so
**Ctrl-C stops them**, and each does a `docker compose down` on start, so there's
normally no need to stop anything explicitly.

Optional first argument is an image tag: `./start-backend-docker.sh v1.0.0`.

**Chaos mode** injects random faults — latency, 4xx/5xx, truncated payloads,
payment failures — so the SDK has real errors to capture. See
[Chaos mode](#chaos-mode) below.

### Prerequisites (macOS)

The scripts wrap `docker compose`, so they need a Docker daemon but **not Docker
Desktop**. This repo uses [Colima](https://github.com/abiosoft/colima):

```bash
brew install colima docker docker-compose
colima start
docker ps          # should print an empty table, not a connection error
```

`colima start` provisions a lightweight Linux VM and points the `docker` CLI at it
— no `DOCKER_HOST` needed. If a script reports `Cannot connect to the Docker
daemon`, Colima isn't running; `colima status` shows the current state.

---

## Layout

```
backend/
├── start-backend-docker.sh         the two scripts you actually use
├── start-backend-chaos-docker.sh
├── shopping_server.py              the server
├── Dockerfile
├── docker-compose.yml
├── docker-compose.o11y.yml         override: attach to tinyolly-network
├── docker-compose.alloy.yml        override: optional Grafana Alloy collector
├── alloy-config.alloy              Alloy pipeline: Grafana Cloud, Honeycomb, ClickStack
├── .env.example                    copy to .env for the Alloy settings
├── requirements.txt
├── images/                         18 product images, committed
└── tools/                          everything occasional — see tools/README.md
```

Everything in [`tools/`](tools/) is for development, publishing, or the
observability variant. You can ignore it for normal use.

---

## API

- **Swagger UI**: `http://localhost:5173/docs`
- **ReDoc**: `http://localhost:5173/redoc`

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

### Deliberate size and latency differences

Endpoints are sized and delayed on purpose, so the dashboard's
"response size by endpoint" and "response time by endpoint" charts show
meaningful spread rather than a flat line. This is independent of chaos mode.

| Endpoint | Size | Latency | What makes it large |
|----------|------|---------|---------------------|
| `GET /api/product/{id}/reviews` | **~330 KB** | 400–1200ms | 150 full reviews with author profiles, photos, seller responses |
| `GET /api/confirmation/{id}` | **~95 KB** | 300–800ms | 8–18 line items, 15 recommendations, 12 "also viewed", policies |
| `GET /api/product/{id}` | **~76 KB** | 200–600ms | Related products, 30 Q&A threads, comparison matrix, price history |
| `GET /api/browse` | ~8 KB | instant | 8 enriched cards with trending data, shipping, promotions |
| `GET /api/welcome` | ~0.2 KB | instant | Store info + 2 promos |
| `POST /api/payment/*` | ~0.2 KB | instant | status, transaction ID, order ID, amount |

---

## Chaos mode

Injects faults probabilistically — each request rolls independently.

Start with it on:

```bash
./start-backend-chaos-docker.sh
```

Or toggle at runtime, without a restart:

```bash
curl -X POST http://localhost:5173/api/chaos/enable
curl -X POST http://localhost:5173/api/chaos/disable
curl http://localhost:5173/api/chaos/status
```

Or per request:

```bash
curl -H "X-Chaos: on" http://localhost:5173/api/browse    # force chaos for this request
curl http://localhost:5173/api/browse?chaos=1
curl -H "X-Chaos: off" http://localhost:5173/api/browse   # exempt this request
curl http://localhost:5173/api/browse?chaos=0
```

### Opting a session out

Chaos is global: while it is on, every client gets it. An individual session can opt out, and nothing else changes for the
other clients. A session can only opt *out*; it cannot turn chaos on while the server has it off.

```bash
# 1. Exempt a session (the id is whatever the client will send as X-Session-Id)
curl -X POST http://localhost:5173/api/chaos/sessions/my-session/disable

# 2. That session's requests now skip chaos
curl -H "X-Session-Id: my-session" http://localhost:5173/api/browse

# Follow the global setting again
curl -X POST http://localhost:5173/api/chaos/sessions/my-session/enable
```

Opt-outs live in memory (cleared on restart), expire after 6 hours (`CHAOS_OPTOUT_TTL_SECONDS`), and are capped at 1000 sessions
(oldest dropped). An opt-out wins over `X-Chaos: on`. The apps do not send `X-Session-Id` yet.

### Fault types

| Fault | Probability | Effect |
|-------|-------------|--------|
| `slow_response` | 15% | 2–12 second delay |
| `http_404` | 8% | Not Found |
| `http_500` | 6% | Internal Server Error |
| `http_503` | 4% | Service Unavailable with Retry-After |
| `slow_images` | 25% | 3–8 second delay on image requests |
| `truncated_json` | 4% | Malformed JSON body |
| `empty_lists` | 7% | Arrays replaced with `[]` |
| `stale_data` | 8% | Mutated price, zero stock, or "[DISCONTINUED]" name |
| `payment_failure` | 12% | Payment endpoints return decline/timeout |
| `session_expiry` | 8% | 401 Unauthorized on checkout/payment |
| `rate_limiting` | 4% | 429 Too Many Requests |

### Control endpoints

| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/chaos/enable` | Turn chaos mode on |
| POST | `/api/chaos/disable` | Turn chaos mode off |
| GET | `/api/chaos/status` | Current config and hit stats |
| POST | `/api/chaos/configure` | Update fault probabilities |
| POST | `/api/chaos/reset-stats` | Zero out hit counters |
| POST | `/api/chaos/sessions/{id}/disable` | Exempt a session (send `X-Session-Id: {id}`) |
| POST | `/api/chaos/sessions/{id}/enable` | Put the session back on the global setting |
| GET | `/api/chaos/sessions` | Opted-out sessions and seconds until each expires |

Raise one fault's rate:

```bash
curl -X POST http://localhost:5173/api/chaos/configure \
  -H "Content-Type: application/json" \
  -d '{"fault_type": "payment_failure", "probability": 0.5}'
```

---

## OpenTelemetry

OpenTelemetry is **opt-in, and not in the default image**. The default `:latest` image runs plain `uvicorn`: it is smaller,
starts faster and never tries to reach a collector. The OpenTelemetry variant is a separate image tag, `:otel`
(`./tools/build.sh otel`, then `./tools/dockerhub-push.sh otel`), built with `--build-arg WITH_OTEL=1`. Run it with
`OTEL_ENABLED=1` and it runs under `opentelemetry-instrument` and exports to a collector:

```bash
TAG=otel OTEL_ENABLED=1 OTEL_EXPORTER_OTLP_ENDPOINT=http://your-collector:4317 docker compose up --pull always
```

`OTEL_ENABLED=1` on the default image just logs a warning and runs without OpenTelemetry.

Traces, metrics and logs all export over OTLP. Logs also go to stdout as
structured JSON with `trace_id` / `span_id` injected when a span is active.

To run against a collector on the external `tinyolly-network` (this start script uses the `:otel` image and sets `OTEL_ENABLED=1` for you):

```bash
docker network create tinyolly-network
./tools/start-backend-docker-o11y.sh
```

The standard start script doesn't need that network — it uses Docker's default
bridge.

### Optional: Grafana Alloy collector

To send the backend's traces, metrics and logs to Grafana Cloud, Honeycomb and ClickStack at the same time, turn on the
bundled [Grafana Alloy](https://grafana.com/docs/alloy/) collector. It is off by default.

```bash
cp .env.example .env     # once; fill in the Grafana Cloud, Honeycomb and ClickStack credentials
# set GRAFANA_ALLOY_ENABLED=true in .env, or per run:
GRAFANA_ALLOY_ENABLED=true ./start-backend-docker.sh
```

With it on, both start scripts add [`docker-compose.alloy.yml`](docker-compose.alloy.yml): the backend uses the `:otel`
image with `OTEL_ENABLED=1` and exports to an `otel-collector` container running Alloy, which batches everything and
sends it to all three vendors ([`alloy-config.alloy`](alloy-config.alloy)). Every credential is required; compose stops
with a message naming any that are missing. Alloy's UI is at `http://localhost:12345`. `.env` is gitignored.

---

## Product images

Served at `/images/{product_id}.jpg` (400×400 JPEG, about 35 KB each) with `Cache-Control: public, max-age=86400` (`IMAGE_CACHE_SECONDS` changes it) plus ETag and Last-Modified, so clients cache them and revalidate cheaply. All 18 are committed and baked into the
image, so there's no generation step for normal use. To refresh them from
[Pexels](https://www.pexels.com/api/), see [tools/README.md](tools/README.md).

## Using compose directly

The start scripts are thin wrappers:

```bash
docker compose up --pull always                # start (latest); Ctrl-C stops
docker compose down                            # remove
TAG=v1.0.0 docker compose up --pull always     # specific version
CHAOS_MODE=1 docker compose up --pull always   # chaos mode
```
