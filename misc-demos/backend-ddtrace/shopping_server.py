"""
ShopDemo Backend — FastAPI server serving realistic e-commerce data for the Sankey demo app.
Run: uvicorn shopping_server:app --host 0.0.0.0 --port 5173 --reload
# Chaos: CHAOS_MODE=1 uvicorn shopping_server:app --host 0.0.0.0 --port 5173
"""

import asyncio
import json
import logging
import os
import random
import string
import sys
import uuid
from datetime import datetime, timedelta

from fastapi import FastAPI, Query, Request
from fastapi.responses import JSONResponse, PlainTextResponse, Response
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel
from starlette.middleware.base import BaseHTTPMiddleware

# ═══════════════════════════════════════════════════════════════════════════
# Structured JSON logging — injects Datadog trace/span IDs when available
# ═══════════════════════════════════════════════════════════════════════════

class DatadogJsonFormatter(logging.Formatter):
    def format(self, record):
        log_data = {
            "timestamp": self.formatTime(record, self.datefmt),
            "severity": record.levelname,
            "message": record.getMessage(),
            "logger": record.name,
        }
        # ddtrace-run + DD_LOGS_INJECTION=true stamps these dotted keys onto every LogRecord
        trace_id = record.__dict__.get("dd.trace_id")
        span_id = record.__dict__.get("dd.span_id")
        if trace_id and trace_id != "0":
            log_data["dd.trace_id"] = trace_id
            log_data["dd.span_id"] = span_id
        if record.exc_info:
            log_data["exception"] = self.formatException(record.exc_info)
        return json.dumps(log_data)

_handler = logging.StreamHandler(sys.stdout)
_handler.setFormatter(DatadogJsonFormatter())
_root_logger = logging.getLogger()
_root_logger.setLevel(logging.INFO)
_root_logger.addHandler(_handler)
logger = logging.getLogger("shopdemo")

# Clear uvicorn's own handlers and let records propagate to root so they get the
# same JSON formatting and Datadog trace correlation as the rest of the app.
for _name in ("uvicorn", "uvicorn.access", "uvicorn.error"):
    _log = logging.getLogger(_name)
    _log.handlers = []
    _log.propagate = True

app = FastAPI(title="ShopDemo API")

# ═══════════════════════════════════════════════════════════════════════════
# Chaos Mode — fault injection for realistic backend failure simulation
# Activated via CHAOS_MODE=1 env var, or POST /api/chaos/enable at runtime
# ═══════════════════════════════════════════════════════════════════════════

CHAOS_CONFIG = {
    "slow_response":    {"enabled": True, "probability": 0.15, "min_delay": 2.0, "max_delay": 12.0},
    "http_404":         {"enabled": True, "probability": 0.08},
    "http_500":         {"enabled": True, "probability": 0.06},
    "http_503":         {"enabled": True, "probability": 0.04},
    "slow_images":      {"enabled": True, "probability": 0.25, "min_delay": 3.0, "max_delay": 8.0},
    "truncated_json":   {"enabled": True, "probability": 0.04},
    "empty_lists":      {"enabled": True, "probability": 0.07},
    "stale_data":       {"enabled": True, "probability": 0.08},
    "payment_failure":  {"enabled": True, "probability": 0.12},
    "session_expiry":   {"enabled": True, "probability": 0.08},
    "rate_limiting":    {"enabled": True, "probability": 0.04},
}

_chaos_enabled = os.environ.get("CHAOS_MODE", "0") == "1"

# Stats tracking
_chaos_stats: dict[str, int] = {k: 0 for k in CHAOS_CONFIG}
_chaos_stats["total_requests"] = 0
_chaos_stats["faults_injected"] = 0


def _chaos_active(request: Request) -> bool:
    """Check if chaos should apply to this request."""
    # Per-request override via header or query param
    if request.headers.get("x-chaos") == "off":
        return False
    if request.headers.get("x-chaos") == "on" or request.query_params.get("chaos") == "1":
        return True
    return _chaos_enabled


def _roll(fault_type: str) -> bool:
    """Roll dice for a specific fault type."""
    cfg = CHAOS_CONFIG.get(fault_type, {})
    if not cfg.get("enabled", False):
        return False
    return random.random() < cfg.get("probability", 0)


class ChaosMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        _chaos_stats["total_requests"] += 1

        # Never apply chaos to chaos control endpoints or health
        path = request.url.path
        if path.startswith("/api/chaos") or path == "/api/health":
            return await call_next(request)

        if not _chaos_active(request):
            return await call_next(request)

        # ── Slow image loading ────────────────────────────────────────
        if path.startswith("/images/") and _roll("slow_images"):
            cfg = CHAOS_CONFIG["slow_images"]
            delay = random.uniform(cfg["min_delay"], cfg["max_delay"])
            _chaos_stats["slow_images"] += 1
            _chaos_stats["faults_injected"] += 1
            await asyncio.sleep(delay)
            return await call_next(request)

        # ── Rate limiting (429) ────────────────────────────────────────
        if _roll("rate_limiting"):
            _chaos_stats["rate_limiting"] += 1
            _chaos_stats["faults_injected"] += 1
            return JSONResponse(
                status_code=429,
                content={"error": "rate_limit_exceeded", "message": "Too many requests. Please retry later."},
                headers={"Retry-After": str(random.randint(5, 30))},
            )

        # ── HTTP 503 Service Unavailable ───────────────────────────────
        if _roll("http_503"):
            _chaos_stats["http_503"] += 1
            _chaos_stats["faults_injected"] += 1
            return JSONResponse(
                status_code=503,
                content={"error": "service_unavailable", "message": "Service temporarily unavailable. Please try again."},
                headers={"Retry-After": str(random.randint(10, 60))},
            )

        # ── HTTP 500 Internal Server Error ─────────────────────────────
        if _roll("http_500"):
            _chaos_stats["http_500"] += 1
            _chaos_stats["faults_injected"] += 1
            errors = [
                "Internal server error",
                "Unexpected error processing request",
                "Database connection timeout",
                "Service dependency failure",
                "Memory allocation error",
            ]
            return JSONResponse(
                status_code=500,
                content={"error": "internal_server_error", "message": random.choice(errors)},
            )

        # ── HTTP 404 Not Found ─────────────────────────────────────────
        if _roll("http_404"):
            _chaos_stats["http_404"] += 1
            _chaos_stats["faults_injected"] += 1
            return JSONResponse(
                status_code=404,
                content={"error": "not_found", "message": "The requested resource was not found."},
            )

        # ── Slow response (latency injection) ─────────────────────────
        if _roll("slow_response"):
            cfg = CHAOS_CONFIG["slow_response"]
            delay = random.uniform(cfg["min_delay"], cfg["max_delay"])
            _chaos_stats["slow_response"] += 1
            _chaos_stats["faults_injected"] += 1
            await asyncio.sleep(delay)

        # ── Session expiry for checkout/payment endpoints ──────────────
        if path.startswith("/api/checkout") or path.startswith("/api/payment"):
            if _roll("session_expiry"):
                _chaos_stats["session_expiry"] += 1
                _chaos_stats["faults_injected"] += 1
                return JSONResponse(
                    status_code=401,
                    content={"error": "session_expired", "message": "Your checkout session has expired. Please start again."},
                )

        # ── Payment failure for payment endpoints ──────────────────────
        if path.startswith("/api/payment"):
            if _roll("payment_failure"):
                _chaos_stats["payment_failure"] += 1
                _chaos_stats["faults_injected"] += 1
                if "androidpay" in path:
                    failure = random.choice([
                        {"status": "timeout", "reason": "Android Pay token validation timeout", "code": "token_timeout"},
                        {"status": "error", "reason": "Android Pay authentication failed", "code": "auth_failed"},
                        {"status": "declined", "reason": "Android Pay account suspended", "code": "account_suspended"},
                        {"status": "error", "reason": "Android Pay NFC handshake failed", "code": "nfc_error"},
                        {"status": "timeout", "reason": "Payment gateway timeout", "code": "gateway_timeout"},
                    ])
                else:
                    failure = random.choice([
                        {"status": "declined", "reason": "Card declined by issuer", "code": "card_declined"},
                        {"status": "declined", "reason": "Insufficient funds", "code": "insufficient_funds"},
                        {"status": "timeout", "reason": "Payment gateway timeout", "code": "gateway_timeout"},
                        {"status": "error", "reason": "Card authentication failed", "code": "auth_failed"},
                        {"status": "declined", "reason": "Suspected fraud", "code": "fraud_suspected"},
                    ])
                return JSONResponse(
                    status_code=402,
                    content={"error": "payment_failed", **failure},
                )

        # ── Empty product lists for listing endpoints ──────────────────
        is_listing = any(path.startswith(p) for p in ["/api/browse", "/api/search", "/api/featured", "/api/categories"])
        if is_listing and _roll("empty_lists"):
            _chaos_stats["empty_lists"] += 1
            _chaos_stats["faults_injected"] += 1
            # Return valid structure but empty data
            if "search" in path:
                return JSONResponse(content={"query": "", "products": [], "result_count": 0})
            elif "featured" in path:
                return JSONResponse(content={"featured_products": [], "banner": {"text": "Coming Soon", "color": "#999"}})
            elif "categories" in path and "/" not in path.replace("/api/categories", ""):
                return JSONResponse(content={"categories": []})
            elif path.startswith("/api/categories/"):
                category_name = path.replace("/api/categories/", "")
                return JSONResponse(content={"category": category_name, "products": [], "total": 0})
            else:
                return JSONResponse(content={"products": [], "total_products": 0})

        # ── Let the real handler run ───────────────────────────────────
        response = await call_next(request)

        # ── Truncated JSON (post-processing) ───────────────────────────
        if response.status_code == 200 and _roll("truncated_json"):
            _chaos_stats["truncated_json"] += 1
            _chaos_stats["faults_injected"] += 1
            # Read the body, truncate it, and return the broken version
            body_bytes = b""
            async for chunk in response.body_iterator:
                body_bytes += chunk if isinstance(chunk, bytes) else chunk.encode()
            if len(body_bytes) > 20:
                cut = random.randint(len(body_bytes) // 3, len(body_bytes) * 2 // 3)
                body_bytes = body_bytes[:cut]
            return Response(content=body_bytes, status_code=200, media_type="application/json")

        # ── Stale data (price mutation on product detail) ──────────────
        if "/api/product/" in path and "/reviews" not in path and response.status_code == 200:
            if _roll("stale_data"):
                _chaos_stats["stale_data"] += 1
                _chaos_stats["faults_injected"] += 1
                body_bytes = b""
                async for chunk in response.body_iterator:
                    body_bytes += chunk if isinstance(chunk, bytes) else chunk.encode()
                try:
                    data = json.loads(body_bytes)
                    # Mutate price, stock, or name to simulate cache inconsistency
                    mutation = random.choice(["price", "stock", "name"])
                    if mutation == "price":
                        data["price"] = round(data.get("price", 99.0) * random.uniform(0.5, 2.0), 2)
                    elif mutation == "stock":
                        data["stock_count"] = 0
                        data["in_stock"] = False
                    else:
                        data["name"] = data.get("name", "Product") + " [DISCONTINUED]"
                    return JSONResponse(content=data, status_code=200)
                except Exception:
                    return Response(content=body_bytes, status_code=200, media_type="application/json")

        return response


# Register chaos middleware
app.add_middleware(ChaosMiddleware)

# ── Chaos control endpoints ───────────────────────────────────────────────

@app.post("/api/chaos/enable")
def chaos_enable():
    global _chaos_enabled
    _chaos_enabled = True
    return {"chaos": "enabled", "config": CHAOS_CONFIG}


@app.post("/api/chaos/disable")
def chaos_disable():
    global _chaos_enabled
    _chaos_enabled = False
    return {"chaos": "disabled"}


@app.get("/api/chaos/status")
def chaos_status():
    return {
        "enabled": _chaos_enabled,
        "config": CHAOS_CONFIG,
        "stats": dict(_chaos_stats),
    }


class ChaosConfigUpdate(BaseModel):
    fault_type: str
    enabled: bool | None = None
    probability: float | None = None


@app.post("/api/chaos/configure")
def chaos_configure(body: ChaosConfigUpdate):
    if body.fault_type not in CHAOS_CONFIG:
        return JSONResponse(status_code=400, content={"error": f"Unknown fault type: {body.fault_type}"})
    if body.enabled is not None:
        CHAOS_CONFIG[body.fault_type]["enabled"] = body.enabled
    if body.probability is not None:
        CHAOS_CONFIG[body.fault_type]["probability"] = max(0.0, min(1.0, body.probability))
    return {"fault_type": body.fault_type, "config": CHAOS_CONFIG[body.fault_type]}


@app.post("/api/chaos/reset-stats")
def chaos_reset_stats():
    for k in _chaos_stats:
        _chaos_stats[k] = 0
    return {"stats": "reset"}


# ═══════════════════════════════════════════════════════════════════════════

# In-memory cart storage (simple demo — resets on server restart)
_cart: dict[str, dict] = {}  # product_id -> {product, quantity}

# Serve generated product images at /images/{product_id}.png
_images_dir = os.path.join(os.path.dirname(__file__), "images")
if os.path.isdir(_images_dir):
    app.mount("/images", StaticFiles(directory=_images_dir), name="images")


# ---------------------------------------------------------------------------
# Request models
# ---------------------------------------------------------------------------

class CartRequest(BaseModel):
    product_id: str = ""
    quantity: int = 1

class WishlistRequest(BaseModel):
    product_id: str = ""

class CheckoutGuestRequest(BaseModel):
    email: str = ""
    shipping_address: dict | None = None

class CheckoutSignInRequest(BaseModel):
    email: str = ""
    password: str = ""

class PaymentCardRequest(BaseModel):
    checkout_session: str = ""
    card_last4: str = ""

class PaymentSessionRequest(BaseModel):
    checkout_session: str = ""

# ---------------------------------------------------------------------------
# Data pools
# ---------------------------------------------------------------------------

PRODUCTS = [
    {"id": "prod_a1b2c3", "name": "Premium Wireless Headphones", "brand": "AudioTech", "price": 299.00, "original_price": 349.00, "category": "Electronics", "rating": 4.8, "review_count": 2431, "sku": "AT-WH-2024-BLK", "stock": 23, "description": "Experience studio-quality sound with active noise cancellation and 40-hour battery life.", "specs": {"battery_life": "40 hours", "driver_size": "40mm", "connectivity": "Bluetooth 5.3", "weight": "250g"}, "colors": ["Black", "Silver", "Navy"]},
    {"id": "prod_d4e5f6", "name": "Smart Watch Pro", "brand": "TechWear", "price": 449.00, "original_price": 499.00, "category": "Electronics", "rating": 4.9, "review_count": 1872, "sku": "TW-SW-2024-SLV", "stock": 15, "description": "Advanced health monitoring with GPS tracking and 7-day battery life.", "specs": {"battery_life": "7 days", "display": "1.9\" AMOLED", "water_resistance": "50m", "weight": "45g"}, "colors": ["Silver", "Black", "Rose Gold"]},
    {"id": "prod_g7h8i9", "name": "Ultra-Slim Laptop", "brand": "CompuMax", "price": 1299.00, "original_price": 1499.00, "category": "Electronics", "rating": 4.7, "review_count": 956, "sku": "CM-UL-2024-GRY", "stock": 8, "description": "Powerful performance in an incredibly thin design. Perfect for professionals on the go.", "specs": {"processor": "M3 Pro", "ram": "16GB", "storage": "512GB SSD", "weight": "1.2kg"}, "colors": ["Space Gray", "Silver"]},
    {"id": "prod_j1k2l3", "name": "Organic Cotton T-Shirt", "brand": "EcoWear", "price": 39.00, "original_price": 45.00, "category": "Clothing", "rating": 4.5, "review_count": 3201, "sku": "EW-TS-2024-WHT", "stock": 150, "description": "Sustainably sourced organic cotton with a relaxed modern fit.", "specs": {"material": "100% Organic Cotton", "fit": "Relaxed", "care": "Machine wash cold", "origin": "Portugal"}, "colors": ["White", "Black", "Navy", "Sage"]},
    {"id": "prod_m4n5o6", "name": "Running Shoes Elite", "brand": "SprintMax", "price": 179.00, "original_price": 199.00, "category": "Sports", "rating": 4.6, "review_count": 1543, "sku": "SM-RS-2024-BLU", "stock": 42, "description": "Lightweight performance running shoes with responsive cushioning.", "specs": {"weight": "220g", "drop": "8mm", "sole": "Carbon plate", "upper": "Engineered mesh"}, "colors": ["Blue", "Black", "Neon Green"]},
    {"id": "prod_p7q8r9", "name": "Ceramic Plant Pot Set", "brand": "HomeBloom", "price": 54.00, "original_price": 65.00, "category": "Home & Garden", "rating": 4.4, "review_count": 892, "sku": "HB-PP-2024-TER", "stock": 67, "description": "Set of 3 handcrafted ceramic pots with drainage holes and bamboo saucers.", "specs": {"sizes": "Small/Medium/Large", "material": "Glazed ceramic", "includes": "Bamboo saucers", "drainage": "Yes"}, "colors": ["Terracotta", "White", "Sage Green"]},
    {"id": "prod_s1t2u3", "name": "Bluetooth Speaker Mini", "brand": "SoundWave", "price": 79.00, "original_price": 99.00, "category": "Electronics", "rating": 4.3, "review_count": 4102, "sku": "SW-BS-2024-RED", "stock": 88, "description": "Portable waterproof speaker with 360-degree sound and 12-hour playtime.", "specs": {"battery_life": "12 hours", "waterproof": "IPX7", "connectivity": "Bluetooth 5.2", "weight": "340g"}, "colors": ["Red", "Black", "Teal"]},
    {"id": "prod_v4w5x6", "name": "Yoga Mat Premium", "brand": "ZenFit", "price": 68.00, "original_price": 79.00, "category": "Sports", "rating": 4.7, "review_count": 2156, "sku": "ZF-YM-2024-PUR", "stock": 34, "description": "Extra-thick non-slip yoga mat with alignment markers and carrying strap.", "specs": {"thickness": "6mm", "material": "Natural rubber + TPE", "size": "183cm x 66cm", "weight": "2.1kg"}, "colors": ["Purple", "Ocean Blue", "Charcoal"]},
    {"id": "prod_y7z8a1", "name": "Stainless Steel Water Bottle", "brand": "HydroLife", "price": 34.00, "original_price": 42.00, "category": "Sports", "rating": 4.8, "review_count": 5678, "sku": "HL-WB-2024-MNT", "stock": 200, "description": "Double-wall vacuum insulated bottle keeps drinks cold 24hrs or hot 12hrs.", "specs": {"capacity": "750ml", "insulation": "Double-wall vacuum", "material": "18/8 Stainless Steel", "weight": "350g"}, "colors": ["Mint", "Black", "White", "Coral"]},
    {"id": "prod_b2c3d4", "name": "Leather Weekender Bag", "brand": "TravelCraft", "price": 189.00, "original_price": 229.00, "category": "Clothing", "rating": 4.6, "review_count": 743, "sku": "TC-WB-2024-BRN", "stock": 19, "description": "Full-grain leather weekender with padded laptop compartment and shoe pocket.", "specs": {"material": "Full-grain leather", "dimensions": "50x30x25cm", "laptop_fit": "Up to 15\"", "weight": "1.8kg"}, "colors": ["Brown", "Black", "Tan"]},
    {"id": "prod_e5f6g7", "name": "Wireless Charging Pad", "brand": "ChargeTech", "price": 45.00, "original_price": 55.00, "category": "Electronics", "rating": 4.4, "review_count": 3421, "sku": "CT-WC-2024-WHT", "stock": 120, "description": "Fast wireless charging pad compatible with all Qi-enabled devices.", "specs": {"output": "15W max", "compatibility": "Qi universal", "indicator": "LED status light", "cable": "USB-C included"}, "colors": ["White", "Black"]},
    {"id": "prod_h8i9j1", "name": "Scented Candle Collection", "brand": "HomeBloom", "price": 42.00, "original_price": 52.00, "category": "Home & Garden", "rating": 4.5, "review_count": 1876, "sku": "HB-SC-2024-AST", "stock": 55, "description": "Set of 3 hand-poured soy wax candles in calming botanical scents.", "specs": {"burn_time": "45 hours each", "wax": "100% Soy", "scents": "Lavender/Cedar/Vanilla", "weight": "280g each"}, "colors": ["Assorted"]},
    {"id": "prod_k2l3m4", "name": "Denim Jacket Classic", "brand": "UrbanEdge", "price": 89.00, "original_price": 110.00, "category": "Clothing", "rating": 4.3, "review_count": 2098, "sku": "UE-DJ-2024-IND", "stock": 38, "description": "Timeless denim jacket with a modern slim fit and brass button details.", "specs": {"material": "100% Cotton Denim", "fit": "Slim", "wash": "Medium indigo", "closure": "Button front"}, "colors": ["Indigo", "Light Wash", "Black"]},
    {"id": "prod_n5o6p7", "name": "Smart Home Hub", "brand": "ConnectAll", "price": 129.00, "original_price": 149.00, "category": "Electronics", "rating": 4.2, "review_count": 1234, "sku": "CA-SH-2024-WHT", "stock": 45, "description": "Central hub for all your smart home devices with voice control.", "specs": {"protocols": "WiFi/Zigbee/Thread", "voice": "Alexa & Google", "display": "4\" touch screen", "speakers": "2x 5W"}, "colors": ["White", "Charcoal"]},
    {"id": "prod_q8r9s1", "name": "Resistance Band Set", "brand": "ZenFit", "price": 29.00, "original_price": 35.00, "category": "Sports", "rating": 4.6, "review_count": 4532, "sku": "ZF-RB-2024-MUL", "stock": 300, "description": "5-piece resistance band set with door anchor and carrying bag.", "specs": {"levels": "5 (10-50 lbs)", "material": "Natural latex", "includes": "Door anchor, handles, ankle straps, bag", "length": "120cm"}, "colors": ["Multi-color"]},
    {"id": "prod_t2u3v4", "name": "Espresso Machine", "brand": "BrewMaster", "price": 399.00, "original_price": 479.00, "category": "Home & Garden", "rating": 4.8, "review_count": 1567, "sku": "BM-EM-2024-SLV", "stock": 12, "description": "Professional-grade espresso machine with built-in grinder and milk frother.", "specs": {"pressure": "15 bar", "grinder": "Conical burr", "tank": "2L", "warm_up": "25 seconds"}, "colors": ["Silver", "Black"]},
    {"id": "prod_w5x6y7", "name": "Bamboo Desk Organizer", "brand": "HomeBloom", "price": 36.00, "original_price": 42.00, "category": "Home & Garden", "rating": 4.3, "review_count": 987, "sku": "HB-DO-2024-NAT", "stock": 75, "description": "Multi-compartment bamboo organizer with phone stand and pen holder.", "specs": {"material": "Sustainable bamboo", "compartments": "6", "dimensions": "28x15x12cm", "finish": "Natural oil"}, "colors": ["Natural"]},
    {"id": "prod_z8a1b2", "name": "Polarized Sunglasses", "brand": "SunVista", "price": 59.00, "original_price": 75.00, "category": "Clothing", "rating": 4.4, "review_count": 2876, "sku": "SV-PS-2024-BLK", "stock": 95, "description": "UV400 polarized lenses in a lightweight titanium frame.", "specs": {"lens": "Polarized UV400", "frame": "Titanium alloy", "weight": "22g", "includes": "Hard case + cloth"}, "colors": ["Black", "Tortoise", "Gold"]},
]

REVIEW_AUTHORS = [
    "Sarah M.", "James K.", "Emily R.", "Michael T.", "Lisa N.",
    "David W.", "Jennifer L.", "Robert P.", "Amanda C.", "Christopher H.",
    "Rachel S.", "Daniel F.", "Olivia B.", "Andrew G.", "Sophia D.",
]

REVIEW_TITLES = [
    "Absolutely love it!", "Best purchase this year", "Exceeded expectations",
    "Great quality", "Worth every penny", "Solid product", "Highly recommend",
    "Perfect for daily use", "Better than expected", "Good but not perfect",
    "Decent for the price", "Would buy again", "Nice design", "Very satisfied",
    "Amazing quality", "Five stars!", "Impressive build", "Great value",
]

REVIEW_BODIES = [
    "I've been using this for a few weeks now and I'm thoroughly impressed. The quality is outstanding. From the moment I opened the package, I could tell this was a premium product. The materials feel durable and well-chosen, the construction is solid with no loose parts or rough edges, and the overall fit and finish exceeds what I expected at this price point. I've compared it side by side with alternatives from three other brands that cost 30-50% more, and honestly this holds its own or even comes out ahead in several categories. The packaging was also thoughtful — everything was well-protected and included clear documentation. Setup took about five minutes and was completely intuitive. After daily use for three weeks, there are zero signs of wear and performance remains consistent. My only minor note is that I wish they offered more color options, but that's purely cosmetic and doesn't affect my rating at all. I've already recommended this to my running group and two of them have purchased it based on my experience. Genuinely one of the best purchases I've made this year, and I say that as someone who researches extensively before buying anything. The customer service team also responded quickly when I had a question about warranty coverage. Would absolutely buy from this brand again.",
    "This exceeded my expectations in every way. The build quality is premium and it works flawlessly. I spent over two weeks researching alternatives before pulling the trigger on this one, reading dozens of reviews, watching comparison videos, and even visiting a physical store to see competing products in person. None of them matched the combination of quality, features, and value that this product offers. The design team clearly put a lot of thought into the user experience — every interaction feels intentional and refined. Small details like the satisfying click of the buttons, the subtle texture of the grip surface, and the way the indicator light pulses gently rather than blinking harshly all contribute to a premium feel. Performance-wise, it delivers exactly what the specs promise with no asterisks or caveats. I've tested it in various conditions including extreme heat, cold, and humidity, and it performs consistently. Battery life actually slightly exceeds the claimed duration, which is refreshing in an industry where specs are often optimistic. The companion app, while not strictly necessary, adds nice quality-of-life features. My partner was so impressed with mine that they ordered one for themselves the next day.",
    "Really happy with this purchase. It arrived quickly and was exactly as described. The shipping was fast — I chose standard delivery expecting 5-7 days but it arrived in just 3. The product was double-boxed for extra protection and came with a nice unboxing experience including a thank-you card from the team. Build quality is excellent for the price, honestly rivaling products that cost twice as much from more established brands. I've been using it every day for about a month now and it still looks and performs like new. The materials show no signs of degradation and the moving parts operate smoothly without any squeaking or stiffness. One thing I particularly appreciate is the attention to sustainability — the packaging is fully recyclable and the product itself uses recycled materials where possible without any compromise to quality. The instruction manual was comprehensive and well-illustrated, though the product is intuitive enough that I barely needed it. Customer support was also excellent when I reached out with a question about accessories — they responded within an hour with detailed, helpful information. Already planning to buy their newer model when it releases next quarter.",
    "Great product for the price point. I've recommended it to several friends already. As someone who has tried literally dozens of similar products over the years, I can say with confidence that this represents the best value currently available in its category. The build quality punches well above its weight class. The engineering team clearly prioritized the things that matter most — core performance, durability, and ease of use — rather than adding unnecessary bells and whistles to inflate the spec sheet. The result is a focused, well-executed product that does its job exceptionally well. I particularly appreciate the modular design which makes maintenance straightforward — you can easily access and replace consumable components without any special tools. This is something competitor products at two or three times the price often get wrong. The included accessories are genuinely useful rather than cheap filler, and the carrying case is sturdy enough for actual use. My only suggestion for improvement would be to include a quick-start guide in addition to the full manual, as it took me a few minutes to find the basic setup instructions amidst all the detailed specifications.",
    "The attention to detail is remarkable. You can tell this was designed with care. Every single aspect of this product shows thoughtful engineering. The way the lid closes with a satisfying magnetic snap, the perfectly balanced weight distribution, the subtle chamfer on every edge that makes it comfortable to hold for extended periods — these aren't things that happen by accident. Someone on the design team clearly advocated for quality at every decision point. I work in product design myself, so I notice these things more than most people, and I'm genuinely impressed. The materials selection deserves special mention — they've chosen a grade of aluminum/polymer that has just the right combination of strength, weight, and tactile feel. The surface finish is uniform and resists fingerprints well. After six weeks of daily use, including some accidental drops onto hard floors, there are only the faintest micro-scratches that you'd need to look for in bright light to notice. Performance metrics align closely with advertised specs, which isn't always the case in this product category.",
    "Performance is excellent. I use it daily and it hasn't let me down once. I bought this as a replacement for a much more expensive competing product that failed after just eight months, so my expectations were honestly not that high — I was just looking for something reliable that wouldn't break the bank. What I got instead was a genuine upgrade in almost every measurable dimension. The response time is noticeably faster, the accuracy is at least as good if not better, and the battery life is substantially longer. I track my daily usage carefully and I'm consistently getting 10-15% more runtime than the stated specification, which is remarkable. The build quality also feels more robust — there's no flex or creak anywhere, and the waterproofing has held up perfectly through several rain-soaked outdoor sessions. The companion app syncs reliably and quickly, unlike my previous product's app which was a constant source of frustration. At this price point, this product is a genuine no-brainer. I've already purchased a second one as a gift.",
    "Good quality overall. There are a few minor things I'd improve but nothing major. Let me start with the positives: build quality is solid, performance meets or exceeds specs, battery life is excellent, and the design is both attractive and functional. The packaging and unboxing experience was also pleasant. Now for the constructive feedback — first, the charging cable is a bit short at only 60cm, which limits placement options during charging. An 80-100cm cable would be much more practical. Second, the status indicator is a bit too dim in bright sunlight, making it hard to confirm the current mode when outdoors. Third, while the app works well functionally, its UI could use a refresh — it feels a bit dated compared to the physical product's modern aesthetic. None of these are dealbreakers by any means, and they don't affect the core functionality at all. If these minor UI and accessory issues were addressed, this would easily be a 5-star product. As it stands, it's still one of the best options available and I'd recommend it without hesitation to anyone in the market.",
    "Fantastic! This is my second one because I liked the first so much. I originally purchased this about a year ago in the Black colorway and was immediately impressed. It quickly became my go-to daily driver, displacing a collection of more expensive alternatives that I'd accumulated over the years. When a friend expressed interest in the Silver version, I ordered one for them and couldn't resist picking up a second one for myself as well — this time in the Navy color — because I wanted a dedicated one for travel. Both units have been equally impressive, which speaks to the consistency of the manufacturing quality. After a full year of near-daily use, my original unit still looks and performs almost identically to the brand-new one. The finish has held up incredibly well with only the most subtle signs of use, and the performance hasn't degraded at all. I've now recommended this product to at least a dozen people and the feedback has been universally positive. This brand has earned a loyal customer.",
    "Solid construction and works as advertised. Very pleased with this purchase. I'll admit I was initially skeptical about purchasing this brand since I hadn't heard of them before and the price seemed almost too good to be true relative to the established names in this space. But after reading through hundreds of reviews and a few detailed YouTube comparisons, I decided to take a shot. So glad I did. The product arrived in premium packaging and the build quality immediately set my concerns to rest — this is a seriously well-made product. The heft is reassuring without being cumbersome, the materials feel high-end, and the assembly fit is precise with no gaps or misalignments. Over the past month, I've put it through increasingly demanding use cases and it has handled everything I've thrown at it without breaking a sweat. Temperature regulation is impressive, noise levels are minimal, and the smart features work reliably without the connectivity issues I've experienced with other brands.",
    "Amazing value for money. Comparable to products costing twice as much. I spent a solid week doing side-by-side comparisons with the three top-selling products in this category, running my own benchmarks and evaluating build quality, features, and long-term durability indicators. Here's the summary: this product matches or exceeds the competition in 7 out of 10 evaluation criteria, ties in 2, and only falls slightly short in 1 (the companion app's notification system, which is a minor quibble). And it costs 40-60% less than the alternatives. The engineering team has clearly focused their budget on the components that matter most — the core performance hardware, the primary interface elements, and structural durability — rather than spending on flashy but functionally meaningless features. The result is a product that feels more expensive than it is in all the ways that count. I've been using it as my primary device for about six weeks now, including travel, outdoor activities, and daily home use. Zero issues, zero complaints about anything that actually affects usability.",
    "The design is sleek and modern. Gets compliments all the time. I chose this primarily for aesthetic reasons — I wanted something that would look good on my desk and match my other gear — but I was pleasantly surprised by how well it performs too. The minimalist design language is executed beautifully, with clean lines, a restrained color palette, and premium materials that look and feel expensive. The display is crisp with excellent viewing angles and good outdoor visibility. The touch interface is responsive and intuitive, and the haptic feedback provides just the right amount of tactile confirmation. But beyond the looks, the actual performance is genuinely excellent. Output quality exceeds what I was getting from my previous setup that cost nearly three times as much. Noise levels are impressively low, power consumption is efficient, and the smart scheduling features have actually changed my daily routine for the better. The companion app — while basic — handles the essential functions well.",
    "Does exactly what it's supposed to. No complaints whatsoever. In a world of overpromising marketing and underdelivering products, it's refreshing to find something that simply works as advertised. I bought this to replace a failing unit from another brand and my primary requirement was reliability above all else. This product delivers exactly that. It starts up quickly, operates consistently, produces the expected results every single time, and has required zero troubleshooting in the two months I've owned it. The initial setup was straightforward — plug in, follow the on-screen prompts, done in under three minutes. The physical build is robust and inspires confidence that it will last. The controls are logically laid out and clearly labeled. The manual is comprehensive but the product is intuitive enough that most users probably won't need it. Power consumption is reasonable and in line with the stated specs.",
    "I was skeptical at first but this product won me over. Truly excellent. My skepticism stemmed from previous bad experiences with products in this price range — I'd tried two other budget options before this one, and both turned out to be disappointing compromises that ended up costing me more in the long run when I had to replace them. So when I ordered this, I was mentally preparing for another letdown. Instead, from the moment I opened the box, it was clear this was different. The packaging was thoughtful, the product felt substantial and well-made, and the first-time setup was smooth and quick. Over the subsequent weeks, my skepticism gradually transformed into genuine enthusiasm as the product consistently performed without issues. The battery life, in particular, has been outstanding — consistently meeting and often exceeding the stated specification by 15-20%. The noise reduction technology works impressively well across a range of environments.",
    "Perfect addition to my daily routine. Can't imagine going without it now. This product has genuinely become indispensable in my day-to-day life. I use it first thing in the morning for about 20 minutes, then intermittently throughout the day, and again before bed. Each time, it performs exactly as expected with no degradation over the course of the day. The quick-charge feature means I rarely have to think about battery management — ten minutes on the charger gets me through an entire day even with heavy use. What really sets this apart from alternatives I've tried is the consistency. Other products in this category tend to have good days and bad days, where performance varies based on temperature, humidity, or how long since the last charge. This one is rock-solid every single time. The build quality supports this consistency — everything feels tight and precise with no loose components or rattling parts.",
    "Top-notch quality. The brand really delivers on their promises. Having now used three different products from this brand, I can confidently say they are one of the most consistent and reliable manufacturers in their space. Each product I've tried has delivered on its specifications, shown excellent build quality, and provided real-world performance that matches or exceeds marketing claims. This particular model continues that trend admirably. The materials are premium without being unnecessarily expensive, the engineering is thoughtful and user-centric, and the warranty support — which I unfortunately had to test once with a previous model — was prompt and hassle-free. The attention to small details like cable management, carrying case quality, and even the weight distribution shows a team that cares about the complete user experience rather than just headline specs. In an increasingly commoditized market, this brand stands out by consistently prioritizing quality and reliability.",
]

FIRST_NAMES = ["Jane", "Alex", "Morgan", "Taylor", "Jordan", "Casey", "Riley", "Quinn", "Avery", "Sam"]
LAST_NAMES = ["Doe", "Johnson", "Smith", "Williams", "Brown", "Davis", "Wilson", "Garcia", "Martinez", "Lee"]

STREETS = [
    "123 Main St", "456 Oak Ave", "789 Pine Rd", "321 Elm Blvd", "654 Maple Dr",
    "987 Cedar Ln", "147 Birch Way", "258 Walnut Ct", "369 Spruce Pl", "741 Willow St",
]
CITIES = [
    ("San Francisco", "CA", "94102"), ("Los Angeles", "CA", "90001"),
    ("New York", "NY", "10001"), ("Chicago", "IL", "60601"),
    ("Austin", "TX", "73301"), ("Seattle", "WA", "98101"),
    ("Portland", "OR", "97201"), ("Denver", "CO", "80201"),
    ("Boston", "MA", "02101"), ("Miami", "FL", "33101"),
]

CARRIERS = [
    ("UPS", "1Z999AA1{num}"),
    ("FedEx", "7489{num}"),
    ("USPS", "9400111899223{num}"),
]

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _random_id(prefix: str, length: int = 6) -> str:
    chars = string.ascii_lowercase + string.digits
    return f"{prefix}_{''.join(random.choices(chars, k=length))}"


def _transaction_id() -> str:
    return f"txn_{uuid.uuid4()}"


def _order_id() -> str:
    return f"ORD-2026-{random.randint(10000, 99999)}"


def _tracking_number() -> str:
    carrier, fmt = random.choice(CARRIERS)
    num = "".join(random.choices(string.digits, k=10))
    return fmt.format(num=num)


def _random_address() -> dict:
    city, state, zipcode = random.choice(CITIES)
    return {
        "street": random.choice(STREETS),
        "city": city,
        "state": state,
        "zip": zipcode,
    }


def _random_name() -> str:
    return f"{random.choice(FIRST_NAMES)} {random.choice(LAST_NAMES)}"


def _image_url(request: Request, product_id: str) -> str:
    """Build an absolute URL for a locally hosted product image."""
    return str(request.base_url) + f"images/{product_id}.png"


def _product_card(p: dict, request: Request) -> dict:
    """Slim product representation for listings."""
    return {
        "id": p["id"],
        "name": p["name"],
        "price": round(p["price"] * random.uniform(0.95, 1.05), 2),
        "rating": p["rating"],
        "review_count": p["review_count"],
        "image_url": _image_url(request, p["id"]),
        "in_stock": p["stock"] > 0,
    }


def _generate_reviews(product_id: str, count: int = 5) -> list:
    reviews = []
    for i in range(count):
        # Generate a detailed response from seller for ~40% of reviews
        seller_response = None
        if random.random() < 0.4:
            seller_response = {
                "author": "ShopDemo Support Team",
                "date": (datetime.now() - timedelta(days=random.randint(0, 30))).strftime("%Y-%m-%d"),
                "body": random.choice([
                    "Thank you so much for your detailed and thoughtful review! We're delighted to hear that the product has met your expectations. Your feedback about the build quality and daily performance is incredibly valuable to our product development team. We've shared your specific comments about the materials and finish with our engineering department. If you ever have any questions or need support, please don't hesitate to reach out to our customer care team at support@shopdemo.com — we're available 24/7 and typically respond within 2 hours during business hours.",
                    "We really appreciate you taking the time to share your experience! It's wonderful to know that you're enjoying the product. We strive to deliver the best possible quality at every price point, and hearing that we've succeeded makes it all worthwhile. Regarding the minor suggestion you mentioned — we've noted it and our product team is actively exploring improvements for the next revision. Thank you for being a valued customer!",
                    "Thank you for your honest and balanced review! We value constructive feedback as it helps us continuously improve. The points you raised about accessory compatibility have been forwarded to our product planning team, and we expect to address them in our next update cycle scheduled for Q3 2026. In the meantime, please feel free to contact our support team if you need any assistance.",
                ]),
            }

        # Generate photo URLs for ~30% of reviews
        photos = []
        if random.random() < 0.3:
            photo_count = random.randint(1, 5)
            photos = [
                {
                    "url": f"https://reviews-cdn.shopdemo.com/{product_id}/review_{i}_photo_{j}.jpg",
                    "thumbnail_url": f"https://reviews-cdn.shopdemo.com/{product_id}/review_{i}_photo_{j}_thumb.jpg",
                    "width": random.choice([1200, 1600, 2400, 3200]),
                    "height": random.choice([900, 1200, 1800, 2400]),
                    "caption": random.choice([
                        "Product as received",
                        "After one month of daily use",
                        "Comparison with the previous version",
                        "Color accuracy in natural light",
                        "Size comparison with common objects",
                        "Packaging and included accessories",
                        "Close-up of the build quality details",
                    ]),
                }
                for j in range(photo_count)
            ]

        reviews.append({
            "review_id": f"rev_{product_id}_{i:04d}",
            "author": random.choice(REVIEW_AUTHORS),
            "author_profile": {
                "reviews_written": random.randint(1, 500),
                "helpful_votes_received": random.randint(0, 2000),
                "member_since": f"20{random.randint(18, 25)}-{random.randint(1,12):02d}",
                "verified_buyer": random.random() > 0.15,
                "top_reviewer": random.random() < 0.1,
                "avatar_url": f"https://avatars.shopdemo.com/{random.choice(REVIEW_AUTHORS).replace(' ', '_').replace('.', '').lower()}.jpg",
            },
            "rating": random.choices([5, 4, 3, 2, 1], weights=[50, 25, 15, 7, 3])[0],
            "title": random.choice(REVIEW_TITLES),
            "body": random.choice(REVIEW_BODIES),
            "pros": random.sample([
                "Excellent build quality", "Great value for money", "Fast shipping",
                "Easy to set up", "Looks premium", "Comfortable to use daily",
                "Battery lasts forever", "Accurate performance", "Lightweight design",
                "Durable materials", "Intuitive controls", "Good customer support",
            ], k=random.randint(2, 5)),
            "cons": random.sample([
                "Instruction manual could be clearer", "Limited color options",
                "Charging cable is short", "App could use polish",
                "Wish it came in more sizes", "Minor cosmetic imperfection",
            ], k=random.randint(0, 2)),
            "date": (datetime.now() - timedelta(days=random.randint(1, 365))).strftime("%Y-%m-%d"),
            "verified_purchase": random.random() > 0.2,
            "helpful_count": random.randint(0, 500),
            "unhelpful_count": random.randint(0, 20),
            "comment_count": random.randint(0, 15),
            "photos": photos,
            "seller_response": seller_response,
            "purchase_date": (datetime.now() - timedelta(days=random.randint(30, 400))).strftime("%Y-%m-%d"),
            "variant_purchased": random.choice(["Black", "Silver", "Navy", "White", "Red"]),
            "usage_duration": random.choice([
                "Less than a week", "1-2 weeks", "1 month", "2-3 months",
                "3-6 months", "6-12 months", "Over a year",
            ]),
        })
    return reviews


def _now_iso() -> str:
    return datetime.now().strftime("%Y-%m-%dT%H:%M:%SZ")


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

@app.get("/api/welcome")
def welcome():
    promos = [
        {"title": "Summer Sale", "discount": "20% off", "code": "SUMMER20"},
        {"title": "Free Shipping", "min_order": 50.00},
        {"title": "New Arrivals", "discount": "15% off first order", "code": "WELCOME15"},
    ]
    return {
        "store_name": "bitdrift shop",
        "tagline": "Premium Shopping Experience",
        "promotions": random.sample(promos, k=2),
        "featured_category": random.choice(["Electronics", "Clothing", "Sports", "Home & Garden"]),
    }


@app.get("/api/browse")
def browse(request: Request):
    sample = random.sample(PRODUCTS, k=min(8, len(PRODUCTS)))
    # Enriched product cards with descriptions, specs, and trending data (~20-30KB)
    enriched = []
    for p in sample:
        card = _product_card(p, request)
        card["description"] = p["description"]
        card["brand"] = p["brand"]
        card["specs"] = p["specs"]
        card["colors"] = p["colors"]
        card["original_price"] = p["original_price"]
        card["category"] = p["category"]
        card["trending_data"] = {
            "views_24h": random.randint(100, 5000),
            "purchases_24h": random.randint(10, 500),
            "cart_adds_24h": random.randint(20, 800),
            "wishlist_adds_24h": random.randint(5, 200),
            "trending_rank": random.randint(1, 100),
        }
        card["shipping_estimate"] = {
            "standard": f"{random.randint(3, 7)} business days",
            "express": f"{random.randint(1, 2)} business days",
            "same_day": random.random() < 0.3,
            "free_shipping": p["price"] >= 50,
        }
        card["promotions"] = random.sample([
            {"type": "percentage", "value": 10, "code": "SAVE10", "expires": "2026-05-01"},
            {"type": "percentage", "value": 15, "code": "SPRING15", "expires": "2026-04-30"},
            {"type": "fixed", "value": 5.00, "code": "5OFF", "expires": "2026-06-01"},
            {"type": "bogo", "value": 0, "code": "BOGO2026", "expires": "2026-04-20"},
        ], k=random.randint(1, 3))
        card["seller_info"] = {
            "name": "ShopDemo Official Store",
            "rating": round(random.uniform(4.5, 5.0), 1),
            "total_sales": random.randint(10000, 500000),
            "member_since": f"20{random.randint(18, 24)}",
            "response_time": f"{random.randint(1, 24)} hours",
        }
        enriched.append(card)
    return {
        "products": enriched,
        "total_products": len(PRODUCTS),
        "browse_metadata": {
            "generated_at": _now_iso(),
            "sort_options": ["relevance", "price_low", "price_high", "rating", "newest", "bestselling"],
            "active_filters": [],
            "available_categories": list({p["category"] for p in PRODUCTS}),
        },
    }


@app.get("/api/search")
def search(request: Request, q: str = Query(default="")):
    query = q.lower()
    if query:
        matches = [p for p in PRODUCTS if query in p["name"].lower() or query in p["category"].lower()]
    else:
        matches = random.sample(PRODUCTS, k=min(6, len(PRODUCTS)))
    return {
        "query": query,
        "products": [_product_card(p, request) for p in matches],
        "result_count": len(matches),
    }


# ─── Cardinality demo endpoint ─────────────────────────────────────────────
# Each request embeds a unique `session` path segment generated by the app,
# making every URL distinct. This creates infinite cardinality in the Bitdrift
# HTTP traffic dashboard, demonstrating the need for Path Templates.
@app.get("/api/inventory/lookup/{item}/{session}")
def inventory_lookup(
    item: str,
    session: str,
):
    # Match item against name/sku prefix — demo only, no strict validation needed
    item_lower = item.lower()
    match = next(
        (p for p in PRODUCTS if item_lower in p["name"].lower() or item_lower in p.get("sku", "").lower()),
        PRODUCTS[0],
    )
    return {
        "item": match["name"],
        "sku": match.get("sku", ""),
        "price": match["price"],
        "stock": match["stock"],
        "session": session,
    }


@app.get("/api/featured")
def featured(request: Request):
    sample = random.sample(PRODUCTS, k=min(6, len(PRODUCTS)))
    badges = ["Staff Pick", "Editor's Choice", "Best Seller", "Trending", "Top Rated"]
    featured_list = []
    for p in sample:
        featured_list.append({
            "id": p["id"],
            "name": p["name"],
            "price": p["price"],
            "badge": random.choice(badges),
            "rating": p["rating"],
            "discount_percent": random.choice([10, 15, 20, 25]),
            "image_url": _image_url(request, p["id"]),
        })
    return {
        "featured_products": featured_list,
        "banner": {"text": "Editor's Choice Collection", "color": "#FFD700"},
    }


@app.get("/api/categories")
def categories():
    category_icons = {"Electronics": "devices", "Clothing": "checkroom", "Home & Garden": "home", "Sports": "sports"}
    counts: dict[str, int] = {}
    for p in PRODUCTS:
        cat = p["category"]
        counts[cat] = counts.get(cat, 0) + 1
    cats = [{"name": name, "product_count": counts.get(name, 0), "icon": icon} for name, icon in category_icons.items()]
    return {"categories": cats}


@app.get("/api/categories/{category_name}")
def category_products(category_name: str, request: Request):
    matches = [p for p in PRODUCTS if p["category"].lower() == category_name.lower()]
    if not matches:
        matches = random.sample(PRODUCTS, k=min(4, len(PRODUCTS)))
    return {
        "category": category_name,
        "products": [_product_card(p, request) for p in matches],
        "total": len(matches),
    }


@app.get("/api/product/{product_id}")
async def product_detail(product_id: str, request: Request):
    # Artificial latency — heavy endpoint (~76KB), 200-600ms to simulate DB joins
    await asyncio.sleep(random.uniform(0.2, 0.6))
    product = next((p for p in PRODUCTS if p["id"] == product_id), None)
    if not product:
        # Return a random product if ID not found (graceful for demo)
        product = random.choice(PRODUCTS)

    # Related products — full cards for 8 products (~15KB)
    related = random.sample(PRODUCTS, k=min(8, len(PRODUCTS)))
    related_products = [_product_card(p, request) for p in related]

    # "Frequently bought together" bundles
    bundle_products = random.sample(PRODUCTS, k=min(4, len(PRODUCTS)))
    frequently_bought = [
        {
            **_product_card(p, request),
            "bundle_discount_percent": random.choice([5, 10, 15]),
            "bundle_price": round(p["price"] * random.uniform(0.85, 0.95), 2),
        }
        for p in bundle_products
    ]

    # Q&A section — 30 questions with detailed answers (~60KB)
    qa_questions = [
        "Is this compatible with...", "How long does the battery last in real use?",
        "What's the warranty coverage?", "Can I use this outdoors?",
        "How does this compare to the previous model?", "Is it worth the upgrade?",
        "Does it come with a carrying case?", "What's the return policy?",
        "Is there a newer version coming soon?", "How heavy is it really?",
        "Can I use it while charging?", "Does it work in extreme temperatures?",
        "What accessories are recommended?", "How is the customer support?",
        "Is the app required or optional?", "How does the noise cancellation compare?",
        "What's the best color option?", "Is there a student discount?",
        "How does it handle humidity?", "Can I connect multiple devices?",
        "Is it safe for children to use?", "What's the maximum range?",
        "How often do firmware updates release?", "Does it support fast charging?",
        "Can I use third-party accessories?", "What's the expected lifespan?",
        "Is there a professional/enterprise version?", "How does it compare to the premium model?",
        "Does it come with international adapters?", "What materials is it made from?",
    ]
    qa_section = [
        {
            "question_id": f"qa_{product_id}_{i:03d}",
            "question": q,
            "asked_by": random.choice(REVIEW_AUTHORS),
            "asked_date": (datetime.now() - timedelta(days=random.randint(1, 300))).strftime("%Y-%m-%d"),
            "vote_count": random.randint(0, 200),
            "answers": [
                {
                    "answer_id": f"ans_{product_id}_{i:03d}_{j}",
                    "author": random.choice(REVIEW_AUTHORS) if j > 0 else "ShopDemo Official",
                    "is_official": j == 0,
                    "body": random.choice([
                        f"Great question! Based on our extensive testing and customer feedback over the past 18 months, the answer is yes — this product is fully designed to handle that use case. Our engineering team specifically optimized for this scenario during the development phase, running over 500 hours of real-world testing across diverse conditions. The key specifications that make this possible are the advanced thermal management system, the reinforced structural components rated for continuous operation, and the intelligent power management algorithms that dynamically adjust resource allocation. We've also received overwhelmingly positive feedback from customers who use it exactly as you're describing, with an average satisfaction rating of 4.8/5.0 for this specific use case. If you have any additional questions or need more detailed technical specifications, our support team is available 24/7 at support@shopdemo.com.",
                        f"I've had mine for about six months now and can share my experience with this exact question. Short answer: absolutely, it works perfectly for that. Longer answer: I was initially concerned about the same thing before I purchased, so I did extensive research including contacting the manufacturer directly. They confirmed that this is one of the primary design considerations for this model. In my personal experience, it has performed flawlessly in this regard — no issues whatsoever across hundreds of uses in varying conditions. I've also spoken with three other owners in my local community group and they all report the same positive experience. The build quality and engineering are clearly designed with your use case in mind. Highly recommend it.",
                        f"According to the official specifications and my own testing, this handles the scenario quite well. The manufacturer has published detailed benchmarks on their website showing performance data across a range of conditions, and my real-world results closely match their claims (within 5-8% variance, which is well within normal tolerances). The key factor is the proprietary technology they developed specifically for this generation of products — it represents a significant improvement over the previous model's approach. I've compiled my own test data over three months of careful measurement and would be happy to share specifics if helpful.",
                    ]),
                    "date": (datetime.now() - timedelta(days=random.randint(0, 200))).strftime("%Y-%m-%d"),
                    "helpful_count": random.randint(0, 150),
                }
                for j in range(random.randint(1, 4))
            ],
        }
        for i, q in enumerate(qa_questions)
    ]

    # Detailed comparison matrix with competitors (~20KB)
    comparison_features = [
        "Battery Life", "Weight", "Water Resistance", "Warranty",
        "Build Material", "Connectivity", "Display Quality", "Noise Level",
        "Operating Temperature", "Charging Speed", "App Ecosystem", "Price",
    ]
    competitors = ["CompetitorX Pro", "RivalBrand Ultra", "BudgetChoice Basic", "PremiumLine Max"]
    comparison_matrix = {
        feature: {
            product["name"]: random.choice(["Excellent", "Very Good", "Good", "Average", "Below Average"]),
            **{comp: random.choice(["Excellent", "Very Good", "Good", "Average", "Below Average"]) for comp in competitors},
        }
        for feature in comparison_features
    }

    # Detailed technical specifications (~5KB)
    extended_specs = {
        **product["specs"],
        "dimensions": {"length": f"{random.uniform(10, 40):.1f}cm", "width": f"{random.uniform(5, 25):.1f}cm", "height": f"{random.uniform(2, 15):.1f}cm"},
        "certifications": random.sample(["CE", "FCC", "RoHS", "UL", "ETL", "Energy Star", "ISO 9001", "IP67", "MIL-STD-810G"], k=random.randint(3, 6)),
        "package_contents": [product["name"], "Quick Start Guide", "Warranty Card", "USB-C Cable", "Carry Pouch", "Cleaning Cloth", "Sticker Pack"],
        "manufacturing": {"country": random.choice(["Japan", "South Korea", "Taiwan", "Germany"]), "facility": f"Factory #{random.randint(1,50)}", "quality_standard": "ISO 9001:2015"},
        "environmental": {"recyclable_packaging": True, "carbon_neutral_shipping": random.random() > 0.5, "recycled_materials_percentage": random.randint(15, 60)},
    }

    # Price history (last 90 days, daily data points — ~10KB)
    price_history = [
        {
            "date": (datetime.now() - timedelta(days=i)).strftime("%Y-%m-%d"),
            "price": round(product["price"] * random.uniform(0.85, 1.15), 2),
            "was_on_sale": random.random() < 0.15,
        }
        for i in range(90)
    ]

    return {
        "id": product["id"],
        "name": product["name"],
        "brand": product["brand"],
        "description": product["description"],
        "price": product["price"],
        "original_price": product["original_price"],
        "sku": product["sku"],
        "in_stock": product["stock"] > 0,
        "stock_count": product["stock"],
        "specs": extended_specs,
        "images": [
            _image_url(request, product["id"]),
        ],
        "colors": product["colors"],
        "rating": product["rating"],
        "review_count": product["review_count"],
        "category": product["category"],
        "related_products": related_products,
        "frequently_bought_together": frequently_bought,
        "questions_and_answers": qa_section,
        "comparison_matrix": comparison_matrix,
        "price_history": price_history,
    }


@app.get("/api/product/{product_id}/reviews")
async def product_reviews(product_id: str):
    # Artificial latency — heaviest endpoint (~330KB), 400-1200ms to simulate review aggregation
    await asyncio.sleep(random.uniform(0.4, 1.2))
    product = next((p for p in PRODUCTS if p["id"] == product_id), None)
    if not product:
        product = random.choice(PRODUCTS)
    breakdown = {
        "5": random.randint(1000, 2000),
        "4": random.randint(300, 600),
        "3": random.randint(50, 200),
        "2": random.randint(20, 80),
        "1": random.randint(5, 40),
    }
    total = sum(breakdown.values())

    # Generate keyword frequency analysis from review corpus
    keyword_analysis = {
        word: random.randint(10, 500)
        for word in [
            "quality", "value", "comfortable", "durable", "premium", "lightweight",
            "battery", "design", "performance", "reliable", "easy", "fast",
            "excellent", "recommend", "sturdy", "impressive", "consistent",
            "sleek", "intuitive", "responsive", "powerful", "versatile",
        ]
    }

    # Monthly rating trend data (last 12 months)
    rating_trends = [
        {
            "month": (datetime.now() - timedelta(days=30 * i)).strftime("%Y-%m"),
            "average_rating": round(random.uniform(4.0, 5.0), 2),
            "review_count": random.randint(50, 400),
            "verified_percentage": round(random.uniform(0.75, 0.95), 2),
        }
        for i in range(12)
    ]

    return {
        "product_id": product["id"],
        "product_name": product["name"],
        "average_rating": product["rating"],
        "total_reviews": total,
        "rating_breakdown": breakdown,
        "keyword_analysis": keyword_analysis,
        "rating_trends": rating_trends,
        "verified_purchase_percentage": round(random.uniform(0.78, 0.95), 2),
        "recommendation_percentage": round(random.uniform(0.85, 0.98), 2),
        # 150 full reviews — this makes the response ~350-500KB
        "reviews": _generate_reviews(product["id"], count=150),
        "pagination": {
            "page": 1,
            "per_page": 150,
            "total_pages": total // 80 + 1,
            "total_results": total,
        },
    }


def _build_cart_response() -> dict:
    """Build a full cart response from the accumulated _cart state."""
    items = []
    subtotal = 0.0
    for pid, entry in _cart.items():
        p = entry["product"]
        qty = entry["quantity"]
        line_total = round(p["price"] * qty, 2)
        subtotal += line_total
        items.append({
            "product_id": p["id"],
            "name": p["name"],
            "quantity": qty,
            "unit_price": p["price"],
            "line_total": line_total,
        })
    subtotal = round(subtotal, 2)
    tax = round(subtotal * 0.09, 2)
    shipping = 0.00 if subtotal >= 50 else 5.99
    total = round(subtotal + tax + shipping, 2)
    return {
        "cart_id": _random_id("cart"),
        "items": items,
        "subtotal": subtotal,
        "tax": tax,
        "shipping": shipping,
        "shipping_method": "Free Standard Shipping" if shipping == 0 else "Standard Shipping",
        "total": total,
        "currency": "USD",
    }


@app.get("/api/cart")
def get_cart():
    return _build_cart_response()


@app.post("/api/cart")
def add_to_cart(body: CartRequest = CartRequest()):
    product_id = body.product_id or random.choice(PRODUCTS)["id"]
    quantity = body.quantity

    product = next((p for p in PRODUCTS if p["id"] == product_id), random.choice(PRODUCTS))

    # Accumulate: if product already in cart, increase quantity
    if product_id in _cart:
        _cart[product_id]["quantity"] += quantity
    else:
        _cart[product_id] = {"product": product, "quantity": quantity}

    return _build_cart_response()


@app.delete("/api/cart/{product_id}")
def remove_from_cart(product_id: str):
    _cart.pop(product_id, None)
    return _build_cart_response()


@app.post("/api/wishlist")
def add_to_wishlist(body: WishlistRequest = WishlistRequest()):
    product_id = body.product_id or random.choice(PRODUCTS)["id"]

    product = next((p for p in PRODUCTS if p["id"] == product_id), random.choice(PRODUCTS))

    # Return a wishlist with 1-3 items for variety
    items = [product] + random.sample(PRODUCTS, k=random.randint(0, 2))
    wishlist_items = []
    for p in items:
        wishlist_items.append({
            "product_id": p["id"],
            "name": p["name"],
            "price": p["price"],
            "added_at": (datetime.now() - timedelta(minutes=random.randint(0, 1440))).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "in_stock": p["stock"] > 0,
        })

    return {
        "wishlist_id": _random_id("wl"),
        "items": wishlist_items,
        "item_count": len(wishlist_items),
    }


@app.post("/api/checkout/guest")
def checkout_guest(body: CheckoutGuestRequest = CheckoutGuestRequest()):
    email = body.email or f"guest{random.randint(100,999)}@example.com"
    name = _random_name()
    address = _random_address()
    address["name"] = name

    subtotal = round(random.uniform(30.0, 500.0), 2)
    tax = round(subtotal * 0.09, 2)
    shipping = 0.00 if subtotal >= 50 else 5.99
    total = round(subtotal + tax + shipping, 2)

    return {
        "checkout_session": _random_id("cs"),
        "email": email,
        "shipping_address": address,
        "order_preview": {
            "items_total": subtotal,
            "tax": tax,
            "shipping": shipping,
            "total": total,
        },
        "available_payment_methods": ["card", "apple_pay"],
    }


@app.post("/api/checkout/signin")
def checkout_signin(body: CheckoutSignInRequest = CheckoutSignInRequest()):
    name = _random_name()
    email = body.email or f"{name.split()[0].lower()}@example.com"

    address = _random_address()
    address["id"] = _random_id("addr")
    address["label"] = random.choice(["Home", "Work", "Other"])

    subtotal = round(random.uniform(30.0, 500.0), 2)
    member_discount = round(subtotal * 0.10, 2)
    discounted = round(subtotal - member_discount, 2)
    tax = round(discounted * 0.09, 2)
    total = round(discounted + tax, 2)

    return {
        "checkout_session": _random_id("cs"),
        "user": {
            "name": name,
            "email": email,
            "member_since": f"20{random.randint(20, 25)}-{random.randint(1,12):02d}-{random.randint(1,28):02d}",
            "loyalty_points": random.randint(100, 5000),
        },
        "saved_addresses": [address],
        "order_preview": {
            "items_total": subtotal,
            "member_discount": -member_discount,
            "tax": tax,
            "shipping": 0.00,
            "total": total,
        },
        "available_payment_methods": ["card", "paypal"],
    }


@app.post("/api/payment/card")
def payment_card(body: PaymentCardRequest = PaymentCardRequest()):
    last4 = body.card_last4 or str(random.randint(1000, 9999))
    amount = round(random.uniform(30.0, 600.0), 2)
    order_id = _order_id()
    _cart.clear()
    return {
        "status": "success",
        "transaction_id": _transaction_id(),
        "order_id": order_id,
        "amount_charged": amount,
        "currency": "USD",
        "payment_method": f"Visa ending in {last4}",
        "timestamp": _now_iso(),
    }


@app.post("/api/payment/applepay")
def payment_applepay(body: PaymentSessionRequest = PaymentSessionRequest()):
    amount = round(random.uniform(30.0, 600.0), 2)
    order_id = _order_id()
    _cart.clear()
    return {
        "status": "success",
        "transaction_id": _transaction_id(),
        "order_id": order_id,
        "amount_charged": amount,
        "currency": "USD",
        "payment_method": "Apple Pay",
        "timestamp": _now_iso(),
    }


@app.post("/api/payment/paypal")
def payment_paypal(body: PaymentSessionRequest = PaymentSessionRequest()):
    amount = round(random.uniform(30.0, 600.0), 2)
    order_id = _order_id()
    _cart.clear()
    paypal_ref = "PAYID-" + "".join(random.choices(string.ascii_uppercase + string.digits, k=8))
    return {
        "status": "success",
        "transaction_id": _transaction_id(),
        "order_id": order_id,
        "amount_charged": amount,
        "currency": "USD",
        "payment_method": "PayPal",
        "paypal_reference": paypal_ref,
        "timestamp": _now_iso(),
    }


@app.post("/api/payment/androidpay")
def payment_androidpay(body: PaymentSessionRequest = PaymentSessionRequest()):
    amount = round(random.uniform(30.0, 600.0), 2)
    order_id = _order_id()
    _cart.clear()
    return {
        "status": "success",
        "transaction_id": _transaction_id(),
        "order_id": order_id,
        "amount_charged": amount,
        "currency": "USD",
        "payment_method": "Android Pay",
        "timestamp": _now_iso(),
    }


@app.get("/api/confirmation/{order_id}")
async def confirmation(order_id: str, request: Request):
    # Artificial latency — large response (~95KB), 300-800ms to simulate order assembly
    await asyncio.sleep(random.uniform(0.3, 0.8))
    # Generate a multi-item order (8-18 items) for a realistic receipt
    item_count = random.randint(8, 18)
    order_items = []
    subtotal = 0.0
    for p in random.choices(PRODUCTS, k=item_count):
        qty = random.randint(1, 3)
        unit_price = round(p["price"] * random.uniform(0.90, 1.05), 2)
        item_total = round(unit_price * qty, 2)
        subtotal += item_total
        order_items.append({
            "product_id": p["id"],
            "name": p["name"],
            "brand": p["brand"],
            "sku": p["sku"],
            "quantity": qty,
            "unit_price": unit_price,
            "line_total": item_total,
            "image_url": _image_url(request, p["id"]),
            "color": random.choice(p["colors"]),
            "category": p["category"],
        })

    subtotal = round(subtotal, 2)
    member_discount = round(subtotal * random.uniform(0.05, 0.15), 2) if random.random() > 0.5 else 0.0
    promo_discount = round(random.uniform(5.0, 25.0), 2) if random.random() > 0.6 else 0.0
    discounted = round(subtotal - member_discount - promo_discount, 2)
    tax = round(discounted * 0.09, 2)
    shipping_cost = 0.00 if discounted >= 50 else 5.99
    total = round(discounted + tax + shipping_cost, 2)

    delivery_days = random.randint(3, 7)
    delivery_date = (datetime.now() + timedelta(days=delivery_days)).strftime("%Y-%m-%d")

    # Shipment tracking events (detailed history — ~8KB)
    tracking = _tracking_number()
    tracking_events = [
        {
            "timestamp": (datetime.now() - timedelta(hours=random.randint(0, 2))).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "status": "Order Confirmed",
            "location": "ShopDemo Fulfillment Center",
            "details": "Your order has been confirmed and is being prepared for shipment. Our warehouse team has begun picking and packing your items.",
        },
        {
            "timestamp": (datetime.now() + timedelta(hours=random.randint(4, 12))).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "status": "Processing",
            "location": "ShopDemo Fulfillment Center, Warehouse B",
            "details": "Items are being picked from inventory and carefully packed with protective materials to ensure safe delivery.",
        },
        {
            "timestamp": (datetime.now() + timedelta(hours=random.randint(12, 24))).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "status": "Shipped",
            "location": random.choice(["San Francisco, CA", "Los Angeles, CA", "Denver, CO", "Chicago, IL"]),
            "details": f"Package has been handed off to the carrier. Tracking number: {tracking}. Estimated delivery: {delivery_date}.",
        },
    ]

    # Recommended products based on order — 15 products with full details (~40KB)
    rec_products = random.sample(PRODUCTS, k=min(15, len(PRODUCTS)))
    recommendations = [
        {
            **_product_card(p, request),
            "recommendation_reason": random.choice([
                "Customers who bought items in your order also bought this",
                "Frequently purchased together with items in your cart",
                "Trending in the same category",
                "Based on your browsing history",
                "Top rated in this category",
                "New arrival you might like",
            ]),
            "match_score": round(random.uniform(0.75, 0.99), 2),
        }
        for p in rec_products
    ]

    # Order policies and terms (~5KB)
    policies = {
        "return_policy": {
            "window_days": 30,
            "conditions": "Items must be in original packaging, unused, and with all tags attached. Electronics must include all original accessories. Return shipping is free for defective items; a $7.99 return shipping fee applies for change-of-mind returns. Refunds are processed within 5-7 business days after we receive the returned item. Gift cards and personalized items are non-returnable.",
            "process": "Initiate a return from your order history page or contact support. You'll receive a prepaid shipping label via email within 24 hours.",
        },
        "warranty": {
            "standard_coverage": "1 year manufacturer warranty against defects in materials and workmanship",
            "extended_available": True,
            "extended_price": round(total * 0.12, 2),
            "extended_duration": "3 years total coverage",
            "coverage_details": "Covers manufacturing defects, premature wear, and component failure under normal use conditions. Does not cover accidental damage, water damage (unless product is rated water-resistant), or cosmetic wear from normal use. Warranty claims are processed within 48 hours with advance replacement available for verified claims.",
        },
        "shipping_terms": "Standard shipping (3-7 business days) is free on orders over $50. Express shipping (1-2 business days) is available for an additional $12.99. Same-day delivery is available in select metropolitan areas for $19.99. All orders are shipped with tracking and insurance up to the total order value.",
    }

    return {
        "order_id": order_id,
        "transaction_id": _transaction_id(),
        "status": "confirmed",
        "items": order_items,
        "pricing": {
            "subtotal": subtotal,
            "member_discount": -member_discount,
            "promo_discount": -promo_discount,
            "tax": tax,
            "shipping": shipping_cost,
            "total": total,
            "currency": "USD",
            "savings_total": round(member_discount + promo_discount, 2),
        },
        "payment_method": random.choice(["Visa ending in 4242", "Apple Pay", "PayPal", "Android Pay", "Mastercard ending in 8888"]),
        "shipping": {
            "method": "Free Standard Shipping" if shipping_cost == 0 else "Standard Shipping",
            "estimated_delivery": delivery_date,
            "tracking_number": tracking,
            "carrier": random.choice(["UPS", "FedEx", "USPS"]),
            "tracking_events": tracking_events,
        },
        "billing_address": {
            "name": _random_name(),
            **_random_address(),
        },
        "shipping_address": {
            "name": _random_name(),
            **_random_address(),
        },
        "placed_at": _now_iso(),
        "recommendations": recommendations,
        "policies": policies,
        # "Customers also viewed" — 12 products with preview reviews (~30KB)
        "customers_also_viewed": [
            {
                **_product_card(p, request),
                "preview_reviews": _generate_reviews(p["id"], count=3),
            }
            for p in random.sample(PRODUCTS, k=min(12, len(PRODUCTS)))
        ],
    }


# ---------------------------------------------------------------------------
# Health check
# ---------------------------------------------------------------------------

@app.get("/api/health")
def health():
    return {"status": "ok", "timestamp": _now_iso()}


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    import uvicorn
    logger.info("ShopDemo API starting", extra={"host": "0.0.0.0", "port": 5173})
    if _chaos_enabled:
        logger.warning("CHAOS MODE ENABLED — faults will be injected into responses")
    uvicorn.run("shopping_server:app", host="0.0.0.0", port=5173, reload=False)
