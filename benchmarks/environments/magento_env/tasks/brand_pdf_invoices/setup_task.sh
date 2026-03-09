#!/bin/bash
# Setup script for Brand PDF Invoices task

echo "=== Setting up Brand PDF Invoices Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Prepare Data: Create the logo file
mkdir -p /home/ga/Documents
# Create a simple valid PNG image (1x1 pixel red dot)
echo -n -e "\x89\x50\x4e\x47\x0d\x0a\x1a\x0a\x00\x00\x00\x0d\x49\x48\x44\x52\x00\x00\x00\x01\x00\x00\x00\x01\x08\x02\x00\x00\x00\x90\x77\x53\xde\x00\x00\x00\x0c\x49\x44\x41\x54\x08\xd7\x63\xf8\xcf\xc0\x00\x00\x03\x01\x01\x00\x18\xdd\x8d\xb0\x00\x00\x00\x00\x49\x45\x4e\x44\xae\x42\x60\x82" > /home/ga/Documents/nestwell_logo.png
chmod 644 /home/ga/Documents/nestwell_logo.png
echo "Created logo file at /home/ga/Documents/nestwell_logo.png"

# 2. Reset Configuration: Clear existing logo/address settings
echo "Resetting sales/identity configuration..."
magento_query "DELETE FROM core_config_data WHERE path IN ('sales/identity/logo', 'sales/identity/logo_html', 'sales/identity/address');"
magento_query "INSERT INTO core_config_data (path, value) VALUES ('sales/identity/address', 'Old Address\nOld City, ST 00000');" 2>/dev/null || true
# Flush cache to ensure config changes take effect (optional but good practice)
php /var/www/html/magento/bin/magento cache:clean config > /dev/null 2>&1

# 3. Create a Pending Order via API (so the agent has something to invoice)
echo "Creating a pending order..."
python3 << 'PYEOF'
import urllib.request
import json
import sys

BASE_URL = "http://localhost"

def api_request(method, endpoint, data=None, token=None):
    url = f"{BASE_URL}/rest/V1/{endpoint}"
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    body = json.dumps(data).encode() if data else None
    try:
        req = urllib.request.Request(url, data=body, headers=headers, method=method)
        resp = urllib.request.urlopen(req)
        return json.loads(resp.read().decode())
    except Exception as e:
        print(f"API Error ({endpoint}): {e}")
        return None

# Get admin token
token = api_request("POST", "integration/admin/token", {"username": "admin", "password": "Admin1234!"})
if not token:
    print("Failed to get admin token")
    sys.exit(1)

# Create a cart
cart_id = api_request("POST", "guest-carts")
if not cart_id:
    # Try getting a customer token if guest fails, but for simplicity let's assume guest works or try admin
    print("Failed to create guest cart")
    sys.exit(1)

# Add item to cart (assuming product ID 1 exists from seeding)
api_request("POST", f"guest-carts/{cart_id}/items", {
    "cartItem": {
        "quote_id": cart_id,
        "sku": "LAPTOP-001", 
        "qty": 1
    }
})

# Set shipping/billing info
address = {
    "region": "California",
    "region_id": 12,
    "region_code": "CA",
    "country_id": "US",
    "street": ["123 Test Ave"],
    "postcode": "90210",
    "city": "Beverly Hills",
    "firstname": "Test",
    "lastname": "Customer",
    "email": "test@example.com",
    "telephone": "555-555-5555",
    "same_as_billing": 1
}
api_request("POST", f"guest-carts/{cart_id}/shipping-information", {
    "addressInformation": {
        "shipping_address": address,
        "billing_address": address,
        "shipping_carrier_code": "flatrate",
        "shipping_method_code": "flatrate"
    }
})

# Place order
order_id = api_request("PUT", f"guest-carts/{cart_id}/order-id", {"paymentMethod": {"method": "checkmo"}})
print(f"Created Order ID: {order_id}")
PYEOF

# 4. Launch Firefox
echo "Ensuring Firefox is running..."
MAGENTO_ADMIN_URL="http://localhost/admin"
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox '$MAGENTO_ADMIN_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 10
fi

# 5. Handle Login if needed
WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1)
if echo "$WINDOW_TITLE" | grep -qi "admin" && ! echo "$WINDOW_TITLE" | grep -qi "dashboard"; then
    echo "Logging in..."
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

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="