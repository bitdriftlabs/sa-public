"""
Download realistic product images from Pexels for all 18 ShopDemo products.

Usage:
    PEXELS_API_KEY=<your-key> python generate_images.py

Requires: pip install Pillow requests
"""

import io
import os
import sys
import time
from urllib.request import Request, urlopen
from urllib.parse import quote_plus

from PIL import Image

# Output directory
OUT_DIR = os.path.join(os.path.dirname(__file__) or ".", "images")

SIZE = 400

# Product catalog: (id, name, search_query)
# search_query is tuned for best Pexels results
PRODUCTS = [
    ("prod_a1b2c3", "Premium Wireless Headphones",     "wireless headphones product"),
    ("prod_d4e5f6", "Smart Watch Pro",                  "smart watch wrist"),
    ("prod_g7h8i9", "Ultra-Slim Laptop",                "laptop computer minimal"),
    ("prod_j1k2l3", "Organic Cotton T-Shirt",           "cotton t-shirt folded"),
    ("prod_m4n5o6", "Running Shoes Elite",              "running shoes pair"),
    ("prod_p7q8r9", "Ceramic Plant Pot Set",            "ceramic plant pot"),
    ("prod_s1t2u3", "Bluetooth Speaker Mini",           "bluetooth speaker portable"),
    ("prod_v4w5x6", "Yoga Mat Premium",                 "yoga mat rolled"),
    ("prod_y7z8a1", "Stainless Steel Water Bottle",     "stainless steel water bottle"),
    ("prod_b2c3d4", "Leather Weekender Bag",            "leather travel bag"),
    ("prod_e5f6g7", "Wireless Charging Pad",            "wireless charger phone"),
    ("prod_h8i9j1", "Scented Candle Collection",        "scented candles"),
    ("prod_k2l3m4", "Denim Jacket Classic",             "denim jacket"),
    ("prod_n5o6p7", "Smart Home Hub",                   "smart home device speaker"),
    ("prod_q8r9s1", "Resistance Band Set",              "resistance bands exercise"),
    ("prod_t2u3v4", "Espresso Machine",                 "espresso machine coffee"),
    ("prod_w5x6y7", "Bamboo Desk Organizer",            "bamboo desk organizer"),
    ("prod_z8a1b2", "Polarized Sunglasses",             "sunglasses product"),
]


def search_pexels(query: str, api_key: str) -> str | None:
    """Search Pexels and return the URL of the best medium-sized photo."""
    url = f"https://api.pexels.com/v1/search?query={quote_plus(query)}&per_page=1&orientation=square"
    req = Request(url, headers={
        "Authorization": api_key,
        "User-Agent": "ShopDemo-ImageGen/1.0",
    })
    try:
        import json
        with urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read())
        photos = data.get("photos", [])
        if not photos:
            return None
        # "medium" is typically 350x350 — close to our target size
        return photos[0]["src"]["medium"]
    except Exception as e:
        print(f"    ⚠ Pexels search failed: {e}")
        return None


def download_image(url: str) -> Image.Image | None:
    """Download an image URL and return a PIL Image."""
    req = Request(url, headers={"User-Agent": "ShopDemo-ImageGen/1.0"})
    try:
        with urlopen(req, timeout=30) as resp:
            return Image.open(io.BytesIO(resp.read()))
    except Exception as e:
        print(f"    ⚠ Download failed: {e}")
        return None


def crop_square_and_resize(img: Image.Image, size: int) -> Image.Image:
    """Center-crop to square, then resize."""
    w, h = img.size
    side = min(w, h)
    left = (w - side) // 2
    top = (h - side) // 2
    img = img.crop((left, top, left + side, top + side))
    return img.resize((size, size), Image.LANCZOS)


def make_placeholder(name: str) -> Image.Image:
    """Fallback: solid gray square with product initials."""
    from PIL import ImageDraw, ImageFont
    img = Image.new("RGB", (SIZE, SIZE), (120, 120, 120))
    draw = ImageDraw.Draw(img)
    initials = "".join(w[0] for w in name.split()[:2]).upper()
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 48)
    except OSError:
        font = ImageFont.load_default()
    draw.text((SIZE // 2, SIZE // 2), initials, fill=(255, 255, 255), font=font, anchor="mm")
    draw.text((SIZE // 2, SIZE - 30), name, fill=(200, 200, 200), font=ImageFont.load_default(), anchor="ms")
    return img


def main():
    api_key = os.environ.get("PEXELS_API_KEY", "").strip()
    if not api_key:
        print("Error: Set PEXELS_API_KEY environment variable.")
        print("  Get a free key at https://www.pexels.com/api/")
        sys.exit(1)

    os.makedirs(OUT_DIR, exist_ok=True)
    success = 0
    fallback = 0

    for pid, name, query in PRODUCTS:
        print(f"  {pid}.png — {name}")
        print(f"    Searching: \"{query}\"")

        photo_url = search_pexels(query, api_key)
        if photo_url:
            img = download_image(photo_url)
            if img:
                img = crop_square_and_resize(img, SIZE)
                img = img.convert("RGB")
                img.save(os.path.join(OUT_DIR, f"{pid}.png"), "PNG")
                print(f"    ✓ Downloaded")
                success += 1
                # Respect Pexels rate limit (200 req/month free, be polite)
                time.sleep(0.5)
                continue

        # Fallback to placeholder
        print(f"    → Using placeholder")
        img = make_placeholder(name)
        img.save(os.path.join(OUT_DIR, f"{pid}.png"), "PNG")
        fallback += 1

    print(f"\nDone! {success} real images, {fallback} placeholders saved to {OUT_DIR}/")


if __name__ == "__main__":
    main()
