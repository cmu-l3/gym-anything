#!/bin/bash
set -e
echo "=== Setting up blanket_order_drawdown task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt

echo "Waiting for ERPNext..."
wait_for_erpnext 300

python3 << 'PYEOF'
import requests, json, sys, time

ERPNEXT_URL = "http://localhost:8080"
session = requests.Session()

# Login
r = session.post(f"{ERPNEXT_URL}/api/method/login", json={"usr": "Administrator", "pwd": "admin"})
if r.status_code != 200:
    print(f"ERROR: Login failed {r.status_code}", file=sys.stderr)
    sys.exit(1)
print("Logged in successfully")

def api_get(doctype, filters=None, fields=None, limit=10):
    params = {"limit_page_length": limit}
    if filters:
        params["filters"] = json.dumps(filters)
    if fields:
        params["fields"] = json.dumps(fields)
    try:
        return session.get(f"{ERPNEXT_URL}/api/resource/{doctype}", params=params).json().get("data", [])
    except Exception as e:
        print(f"API get error: {e}", file=sys.stderr)
        return []

def get_or_create(doctype, filters, values):
    existing = api_get(doctype, filters)
    if existing:
        name = existing[0]["name"]
        print(f"  Found existing {doctype}: {name}")
        return name
    r = session.post(f"{ERPNEXT_URL}/api/resource/{doctype}", json=values)
    if r.status_code in (200, 201):
        name = r.json().get("data", {}).get("name", "unknown")
        print(f"  Created {doctype}: {name}")
        return name
    print(f"  ERROR creating {doctype}: {r.status_code} {r.text[:300]}", file=sys.stderr)
    return None

# Wait for master data
print("Waiting for ERPNext master data (Company)...")
master_ready = False
for attempt in range(60):
    try:
        companies = api_get("Company", [["company_name", "=", "Wind Power LLC"]])
        if companies:
            master_ready = True
            break
    except:
        pass
    time.sleep(5)

if not master_ready:
    print("ERROR: ERPNext master data not available after 5 minutes", file=sys.stderr)
    sys.exit(1)

# Ensure Eagle Hardware
get_or_create("Supplier",
              [["supplier_name", "=", "Eagle Hardware"]],
              {"supplier_name": "Eagle Hardware",
               "supplier_type": "Company",
               "supplier_group": "All Supplier Groups"})

# Ensure Base Plate
item_exists = api_get("Item", [["item_code", "=", "Base Plate"]])
if not item_exists:
    r = session.post(f"{ERPNEXT_URL}/api/resource/Item", json={
        "item_code": "Base Plate",
        "item_name": "Base Plate",
        "item_group": "All Item Groups",
        "stock_uom": "Nos",
        "is_stock_item": 1,
        "is_purchase_item": 1,
        "description": "Base Plate for Wind Turbine"
    })
    if r.status_code in (200, 201):
        print("  Created Item: Base Plate")
    else:
        print(f"  ERROR creating Item: {r.status_code} {r.text[:200]}", file=sys.stderr)
else:
    print("  Found existing Item: Base Plate")

# Get initial counts
bo_count = len(api_get("Blanket Order", [["supplier", "=", "Eagle Hardware"], ["docstatus", "=", 1]], limit=100))
po_count = len(api_get("Purchase Order", [["supplier", "=", "Eagle Hardware"], ["docstatus", "=", 1]], limit=100))

baseline = {
    "initial_bo_count": bo_count,
    "initial_po_count": po_count
}

with open("/tmp/blanket_order_drawdown_baseline.json", "w") as f:
    json.dump(baseline, f)

PYEOF

# Navigate browser to Blanket Order list
echo "Navigating browser to Blanket Order list..."
ensure_firefox_at "http://localhost:8080/app/blanket-order"
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="