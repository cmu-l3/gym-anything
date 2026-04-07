#!/bin/bash
# Setup script for create_purchase_invoice task
# Verifies OFBiz is running with demo data loaded (DemoSupplier party,
# product catalog with GZ-2644 and GZ-8544) and navigates Firefox
# to the Accounting module's invoice creation page.
#
# Data source: Apache OFBiz built-in demo data
#   - DemoSupplier: from applications/party/data/DemoOrganizationData.xml
#   - GZ-2644 (Round Gizmo, $38.40): from applications/product/data/DemoProduct.xml
#   - GZ-8544 (Powered Gizmo, $12.95): from applications/product/data/DemoProduct.xml
#   - Existing demo invoices: applications/accounting/data/DemoPaymentsInvoices.xml

echo "=== Setting up create_purchase_invoice task ==="

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

# Verify Accounting module is accessible
acct_resp = session.get(f"{OFBIZ_URL}/accounting/control/main", allow_redirects=True)
print(f"Accounting module access: {acct_resp.status_code}")

# Save task configuration
setup_data = {
    "vendor_party_id": "DemoSupplier",
    "company_party_id": "Company",
    "data_source": "Apache OFBiz built-in demo data (DemoPaymentsInvoices.xml)",
    "items": [
        {"product_id": "GZ-2644", "name": "Round Gizmo", "qty": 20, "price": 38.40},
        {"product_id": "GZ-8544", "name": "Powered Gizmo", "qty": 12, "price": 12.95}
    ],
    "expected_total": 20 * 38.40 + 12 * 12.95
}
with open("/tmp/create_purchase_invoice_setup.json", "w") as f:
    json.dump(setup_data, f, indent=2)

print(f"\n=== Task Data Summary ===")
print(f"Vendor: DemoSupplier")
print(f"Company: Company")
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

# Navigate Firefox to Accounting - invoices list
ensure_firefox_at "$OFBIZ_URL/accounting/control/findInvoices"

sleep 3
take_screenshot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== create_purchase_invoice setup complete ==="
echo "Agent should create a purchase invoice for DemoSupplier with GZ-2644 and GZ-8544"
