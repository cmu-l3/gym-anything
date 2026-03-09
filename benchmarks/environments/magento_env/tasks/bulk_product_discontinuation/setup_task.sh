#!/bin/bash
# Setup script for Bulk Product Discontinuation task

echo "=== Setting up Bulk Product Discontinuation Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ==============================================================================
# 1. GENERATE DATA (Python + REST API)
# ==============================================================================
echo "Generating product data..."

# We use a python script to inject products via REST API to ensure clean state
# This avoids complex direct SQL insertions for EAV structures
cat > /tmp/seed_products.py << 'PYEOF'
import urllib.request
import json
import sys
import time

BASE_URL = "http://localhost/rest/V1"
TOKEN = ""

def get_token():
    url = "http://localhost/rest/V1/integration/admin/token"
    data = json.dumps({"username": "admin", "password": "Admin1234!"}).encode()
    headers = {"Content-Type": "application/json"}
    req = urllib.request.Request(url, data=data, headers=headers, method="POST")
    try:
        resp = urllib.request.urlopen(req)
        return json.loads(resp.read().decode())
    except Exception as e:
        print(f"Error getting token: {e}")
        return None

def create_product(sku, name, price, tax_class_id=2):
    url = f"{BASE_URL}/products"
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {TOKEN}"
    }
    
    product_data = {
        "product": {
            "sku": sku,
            "name": name,
            "attribute_set_id": 4, # Default
            "price": price,
            "status": 1, # Enabled
            "visibility": 4, # Catalog, Search
            "type_id": "simple",
            "extension_attributes": {
                "stock_item": {
                    "qty": 100,
                    "is_in_stock": True
                }
            },
            "custom_attributes": [
                {"attribute_code": "tax_class_id", "value": str(tax_class_id)}
            ]
        }
    }
    
    data = json.dumps(product_data).encode()
    req = urllib.request.Request(url, data=data, headers=headers, method="POST")
    
    try:
        urllib.request.urlopen(req)
        # print(f"Created {sku}")
        return True
    except urllib.error.HTTPError as e:
        print(f"Failed {sku}: {e.code} - {e.read().decode()}")
        return False
    except Exception as e:
        print(f"Error {sku}: {e}")
        return False

# Execution
TOKEN = get_token()
if not TOKEN:
    sys.exit(1)

# Create 25 Legacy products (Target)
print("Creating 25 Legacy products...")
for i in range(1, 26):
    sku = f"LEG-{i:03d}"
    create_product(sku, f"Legacy Item {i}", 10.00, 2) # Taxable Goods

# Create 15 Core products (Protected)
print("Creating 15 Core products...")
for i in range(1, 16):
    sku = f"CORE-{i:03d}"
    create_product(sku, f"Core Product {i}", 50.00, 2) # Taxable Goods

print("Data seeding complete.")
PYEOF

# Run the seeding script
python3 /tmp/seed_products.py

# Reindex to ensure they show up in grid/search immediately
echo "Reindexing..."
php /var/www/html/magento/bin/magento indexer:reindex > /dev/null 2>&1

# ==============================================================================
# 2. PREPARE BROWSER
# ==============================================================================
echo "Preparing browser..."

MAGENTO_ADMIN_URL="http://localhost/admin/catalog/product/"

# Start Firefox if not running
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$MAGENTO_ADMIN_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 8
fi

# Focus window
if wait_for_window "firefox\|mozilla\|Magento" 30; then
    WID=$(get_firefox_window_id)
    if [ -n "$WID" ]; then
        focus_window "$WID"
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi
fi

# Check for login
sleep 2
WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1)
if echo "$WINDOW_TITLE" | grep -qi "admin" && ! echo "$WINDOW_TITLE" | grep -qi "dashboard\|products"; then
    echo "Logging in..."
    DISPLAY=:1 xdotool mousemove 960 540 click 1
    sleep 0.5
    DISPLAY=:1 xdotool key Tab
    sleep 0.2
    DISPLAY=:1 xdotool key ctrl+a
    DISPLAY=:1 xdotool type --clearmodifiers "admin"
    sleep 0.5
    DISPLAY=:1 xdotool key Tab
    sleep 0.2
    DISPLAY=:1 xdotool type --clearmodifiers "Admin1234!"
    sleep 0.5
    DISPLAY=:1 xdotool key Return
    
    # Wait for redirect
    sleep 8
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="