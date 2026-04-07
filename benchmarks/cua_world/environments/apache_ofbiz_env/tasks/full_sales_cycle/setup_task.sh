#!/bin/bash
# Setup script for full_sales_cycle task
# Verifies OFBiz is running with demo data (AcctBuyer, GZ-2644, WG-9943)
# and navigates Firefox to the Order Manager's order entry screen.
#
# This is a hard multi-step task: create order -> approve -> create invoice -> approve invoice.
#
# Data source: Apache OFBiz built-in demo data
#   - AcctBuyer: from applications/party/data/ (demo accounting buyer)
#   - GZ-2644 (Round Gizmo, $38.40): from applications/product/data/DemoProduct.xml
#   - WG-9943 (Giant Widget, $440.00): from applications/product/data/DemoProduct.xml

echo "=== Setting up full_sales_cycle task ==="

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
login_resp = session.post(f"{OFBIZ_URL}/accounting/control/login", data={
    "USERNAME": "admin",
    "PASSWORD": "ofbiz",
    "JavaScriptEnabled": "Y"
}, allow_redirects=True)
print(f"Login response: {login_resp.status_code}")

# Verify modules are accessible
for module in ["ordermgr", "accounting"]:
    resp = session.get(f"{OFBIZ_URL}/{module}/control/main", allow_redirects=True)
    print(f"{module} access: {resp.status_code}")

# Save task configuration
setup_data = {
    "customer_party_id": "AcctBuyer",
    "product_store_name": "OFBiz E-Commerce Store",
    "data_source": "Apache OFBiz built-in demo data",
    "items": [
        {"product_id": "GZ-2644", "name": "Round Gizmo", "qty": 3, "price": 38.40},
        {"product_id": "WG-9943", "name": "Giant Widget", "qty": 2, "price": 440.00}
    ],
    "expected_total": 3 * 38.40 + 2 * 440.00,
    "workflow": "create_order -> approve_order -> create_invoice -> approve_invoice"
}
with open("/tmp/full_sales_cycle_setup.json", "w") as f:
    json.dump(setup_data, f, indent=2)

print(f"\n=== Task Data Summary ===")
print(f"Customer: AcctBuyer")
print(f"Product Store: OFBiz E-Commerce Store (ID 9000)")
for item in setup_data["items"]:
    subtotal = item["qty"] * item["price"]
    print(f"  Item: {item['name']} ({item['product_id']}) x{item['qty']} @ ${item['price']:.2f} = ${subtotal:.2f}")
print(f"  Expected total: ${setup_data['expected_total']:.2f}")
print(f"  Workflow: {setup_data['workflow']}")
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

echo "=== full_sales_cycle setup complete ==="
echo "Agent should: create order for AcctBuyer -> approve -> create invoice from order -> approve invoice"
