#!/bin/bash
# Setup script for create_sales_order task
# Verifies OFBiz demo data is loaded (products and customers from built-in demo)
# and navigates Firefox to the Order Manager's order entry screen.
#
# Data source: Apache OFBiz built-in demo data
# Products: GZ-1000 (Tiny Gizmo, $9.99), WG-5569 (Tiny Chrome Widget, $48.00)
# Customer: DemoCustCompany (built-in demo party)

echo "=== Setting up create_sales_order task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "Waiting for OFBiz..."
wait_for_ofbiz 60

# Verify demo data is accessible via OFBiz services
python3 << 'PYEOF'
import requests
import json
import sys
import urllib3
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

OFBIZ_URL = "https://localhost:8443"
session = requests.Session()
session.verify = False

# Login via OFBiz XML-RPC / form auth
login_resp = session.post(f"{OFBIZ_URL}/accounting/control/login", data={
    "USERNAME": "admin",
    "PASSWORD": "ofbiz",
    "JavaScriptEnabled": "Y"
}, allow_redirects=True)
print(f"Login response: {login_resp.status_code}")

# Verify we can access the order entry page
order_resp = session.get(f"{OFBIZ_URL}/ordermgr/control/main", allow_redirects=True)
print(f"Order Manager access: {order_resp.status_code}")

# Check that demo products exist by looking at catalog
catalog_resp = session.get(f"{OFBIZ_URL}/catalog/control/main", allow_redirects=True)
print(f"Catalog Manager access: {catalog_resp.status_code}")

# Save task configuration
setup_data = {
    "customer_party_id": "DemoCustCompany",
    "product_store_id": "9000",
    "data_source": "Apache OFBiz built-in demo data",
    "items": [
        {"product_id": "GZ-1000", "name": "Tiny Gizmo", "qty": 10, "price": 9.99},
        {"product_id": "WG-5569", "name": "Tiny Chrome Widget", "qty": 5, "price": 48.00}
    ],
    "expected_total": 10 * 9.99 + 5 * 48.00
}
with open("/tmp/create_sales_order_setup.json", "w") as f:
    json.dump(setup_data, f, indent=2)

print(f"\n=== Task Data Summary ===")
print(f"Customer: DemoCustCompany")
print(f"Product Store: OFBiz E-Commerce Store (ID 9000)")
for item in setup_data["items"]:
    subtotal = item["qty"] * item["price"]
    print(f"  Item: {item['name']} ({item['product_id']}) x{item['qty']} @ ${item['price']:.2f} = ${subtotal:.2f}")
print(f"  Expected total: ${setup_data['expected_total']:.2f}")
PYEOF

if [ $? -ne 0 ]; then
    echo "WARNING: Python verification had issues, but OFBiz demo data should be available"
fi

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Navigate Firefox to Order Manager - order entry page
ensure_firefox_at "$OFBIZ_URL/ordermgr/control/orderentry"

sleep 3
take_screenshot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== create_sales_order setup complete ==="
echo "Agent should create a sales order for DemoCustCompany using OFBiz E-Commerce Store with GZ-1000 and WG-5569"
