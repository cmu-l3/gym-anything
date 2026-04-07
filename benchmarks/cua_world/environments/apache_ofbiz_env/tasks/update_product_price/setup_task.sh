#!/bin/bash
# Setup script for update_product_price task
# Verifies OFBiz is running with demo data (product WG-1111 exists)
# and navigates Firefox to the Catalog Manager's product page for WG-1111.
#
# Data source: Apache OFBiz built-in demo data
#   - WG-1111 (Micro Chrome Widget): from applications/product/data/DemoProduct.xml
#   - Default price: $59.99
#   - Description: "A very small chrome widget"

echo "=== Setting up update_product_price task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "Waiting for OFBiz..."
wait_for_ofbiz 60

# Verify demo data accessibility
python3 << 'PYEOF'
import requests
import json
import sys
import urllib3
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

OFBIZ_URL = "https://localhost:8443"
session = requests.Session()
session.verify = False

# Login
login_resp = session.post(f"{OFBIZ_URL}/catalog/control/login", data={
    "USERNAME": "admin",
    "PASSWORD": "ofbiz",
    "JavaScriptEnabled": "Y"
}, allow_redirects=True)
print(f"Login response: {login_resp.status_code}")

# Verify Catalog module is accessible
cat_resp = session.get(f"{OFBIZ_URL}/catalog/control/main", allow_redirects=True)
print(f"Catalog Manager access: {cat_resp.status_code}")

# Save task configuration
setup_data = {
    "product_id": "WG-1111",
    "product_name": "Micro Chrome Widget",
    "data_source": "Apache OFBiz built-in demo data (DemoProduct.xml)",
    "original_price": 59.99,
    "new_price": 49.99,
    "original_description": "A very small chrome widget",
    "new_description": "Limited Time Offer - A very small chrome widget"
}
with open("/tmp/update_product_price_setup.json", "w") as f:
    json.dump(setup_data, f, indent=2)

print(f"\n=== Task Data Summary ===")
print(f"Product: {setup_data['product_name']} ({setup_data['product_id']})")
print(f"Current price: ${setup_data['original_price']:.2f}")
print(f"Target price: ${setup_data['new_price']:.2f}")
print(f"Current description: {setup_data['original_description']}")
print(f"Target description: {setup_data['new_description']}")
PYEOF

if [ $? -ne 0 ]; then
    echo "WARNING: Python verification had issues, but OFBiz demo data should be available"
fi

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Navigate Firefox to Catalog Manager - product view for WG-1111
ensure_firefox_at "$OFBIZ_URL/catalog/control/EditProduct?productId=WG-1111"

sleep 3
take_screenshot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== update_product_price setup complete ==="
echo "Agent should update WG-1111 price from \$59.99 to \$49.99 and add 'Limited Time Offer' to description"
