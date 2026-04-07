#!/bin/bash
# Setup script for manufacturing_bom_setup task
# Verifies OFBiz is running with demo data (GZ-1000 and GZ-2644 exist as
# component products) and navigates Firefox to the Catalog Manager for
# creating a new product.
#
# This is a hard multi-module task: create product in Catalog -> create BOM in Manufacturing.
#
# Data source: Apache OFBiz built-in demo data
#   - GZ-1000 (Tiny Gizmo): from applications/product/data/DemoProduct.xml
#   - GZ-2644 (Round Gizmo): from applications/product/data/DemoProduct.xml
#   - New product GIZMO-KIT-01 will be created by the agent

echo "=== Setting up manufacturing_bom_setup task ==="

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

# Verify modules are accessible
for module in ["catalog", "manufacturing"]:
    resp = session.get(f"{OFBIZ_URL}/{module}/control/main", allow_redirects=True)
    print(f"{module} access: {resp.status_code}")

# Save task configuration
setup_data = {
    "new_product_id": "GIZMO-KIT-01",
    "new_product_name": "Gizmo Starter Kit",
    "data_source": "Apache OFBiz built-in demo data",
    "components": [
        {"product_id": "GZ-1000", "name": "Tiny Gizmo", "qty": 2},
        {"product_id": "GZ-2644", "name": "Round Gizmo", "qty": 1}
    ],
    "workflow": "create_product_in_catalog -> navigate_to_manufacturing -> create_bom -> add_components"
}
with open("/tmp/manufacturing_bom_setup.json", "w") as f:
    json.dump(setup_data, f, indent=2)

print(f"\n=== Task Data Summary ===")
print(f"New Product: {setup_data['new_product_name']} ({setup_data['new_product_id']})")
for comp in setup_data["components"]:
    print(f"  Component: {comp['name']} ({comp['product_id']}) x{comp['qty']}")
print(f"  Workflow: {setup_data['workflow']}")
PYEOF

if [ $? -ne 0 ]; then
    echo "WARNING: Python verification had issues, but OFBiz demo data should be available"
fi

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Navigate Firefox to Catalog Manager - create new product page
ensure_firefox_at "$OFBIZ_URL/catalog/control/EditProduct"

sleep 3
take_screenshot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== manufacturing_bom_setup setup complete ==="
echo "Agent should: create product GIZMO-KIT-01 in Catalog -> create BOM in Manufacturing with GZ-1000 x2 and GZ-2644 x1"
