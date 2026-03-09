#!/bin/bash
# Setup script for Bundle Product task

echo "=== Setting up Bundle Product Task ==="

source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# Record initial product count
echo "Recording initial product count..."
INITIAL_COUNT=$(get_product_count 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_product_count

# =============================================================================
# PRE-CREATE COMPONENT PRODUCTS
# =============================================================================
# The agent needs these simple products to exist to add them to the bundle.
# We create them via Python script interacting with Magento REST API.

echo "Creating component simple products..."

cat > /tmp/create_components.py << 'PYEOF'
import urllib.request
import json
import sys

BASE_URL = "http://localhost"
ADMIN_USER = "admin"
ADMIN_PASS = "Admin1234!"

def api_request(method, endpoint, data=None, token=None):
    url = f"{BASE_URL}/rest/V1/{endpoint}"
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    body = json.dumps(data).encode() if data else None
    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        resp = urllib.request.urlopen(req)
        return json.loads(resp.read().decode())
    except Exception as e:
        # Ignore errors if product already exists
        return None

# Get Admin Token
print("Getting admin token...")
token = api_request("POST", "integration/admin/token", {"username": ADMIN_USER, "password": ADMIN_PASS})
if not token:
    print("Failed to get token")
    sys.exit(1)

# Define products to create
products = [
    {"sku": "TENT-BASIC", "name": "Basic 2-Person Tent", "price": 89.99, "qty": 100},
    {"sku": "TENT-FAMILY", "name": "Family 4-Person Tent", "price": 179.99, "qty": 50},
    {"sku": "SLEEP-LITE", "name": "Lightweight Sleeping Bag", "price": 49.99, "qty": 200},
    {"sku": "SLEEP-WINTER", "name": "Winter Insulated Sleeping Bag", "price": 99.99, "qty": 150},
    {"sku": "COOK-STOVE", "name": "Portable Camp Stove", "price": 39.99, "qty": 80},
    {"sku": "COOK-SET", "name": "Camp Cookware Set", "price": 59.99, "qty": 120}
]

for p in products:
    print(f"Creating {p['sku']}...")
    payload = {
        "product": {
            "sku": p["sku"],
            "name": p["name"],
            "attribute_set_id": 4, # Default
            "price": p["price"],
            "status": 1,
            "visibility": 4,
            "type_id": "simple",
            "extension_attributes": {
                "stock_item": {
                    "qty": p["qty"],
                    "is_in_stock": True
                }
            }
        }
    }
    api_request("POST", "products", payload, token)

print("Component products created.")
PYEOF

python3 /tmp/create_components.py

# =============================================================================
# BROWSER SETUP
# =============================================================================

echo "Ensuring Firefox is running..."
MAGENTO_ADMIN_URL="http://localhost/admin"

if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$MAGENTO_ADMIN_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 10
fi

# Wait for window
wait_for_window "firefox\|mozilla\|Magento" 60

# Focus window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 2
fi

# Login if needed (using xdotool as fallback for session restore)
WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1)
if echo "$WINDOW_TITLE" | grep -qi "admin" && ! echo "$WINDOW_TITLE" | grep -qi "dashboard"; then
    echo "Attempting auto-login..."
    sleep 2
    DISPLAY=:1 xdotool mousemove 960 540 click 1
    sleep 0.5
    DISPLAY=:1 xdotool key Tab
    sleep 0.3
    DISPLAY=:1 xdotool key ctrl+a
    DISPLAY=:1 xdotool type --clearmodifiers "admin"
    sleep 0.5
    DISPLAY=:1 xdotool key Tab
    sleep 0.3
    DISPLAY=:1 xdotool type --clearmodifiers "Admin1234!"
    sleep 0.5
    DISPLAY=:1 xdotool key Return
    sleep 10
fi

# Clean up any previous attempts at this bundle
echo "Cleaning up previous attempts..."
magento_query "DELETE FROM catalog_product_entity WHERE sku='CAMP-BUNDLE-001'" 2>/dev/null || true
magento_query "DELETE FROM url_rewrite WHERE entity_type='product' AND request_path='ultimate-camping-kit.html'" 2>/dev/null || true

# Initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Navigate to Catalog > Products to begin."