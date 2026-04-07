#!/bin/bash
# Setup script for manufacturing_routing_and_bom task
# Creates raw material items and the FG item (Advanced Wind Turbine)
# Ensures no pre-existing BOMs or Workstations/Operations with the target names exist.

set -e
echo "=== Setting up manufacturing_routing_and_bom ==="

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "Waiting for ERPNext..."
wait_for_erpnext 300

python3 << 'PYEOF'
import requests, json, sys, time

ERPNEXT_URL = "http://localhost:8080"
session = requests.Session()

# --- Login ---
r = session.post(f"{ERPNEXT_URL}/api/method/login",
                 json={"usr": "Administrator", "pwd": "admin"})
if r.status_code != 200:
    print(f"ERROR: Login failed {r.status_code}", file=sys.stderr)
    sys.exit(1)
print("Logged in successfully")

def api_get(doctype, filters=None, fields=None, limit=1):
    params = {"limit_page_length": limit}
    if filters:
        params["filters"] = json.dumps(filters)
    if fields:
        params["fields"] = json.dumps(fields)
    return session.get(f"{ERPNEXT_URL}/api/resource/{doctype}", params=params).json().get("data", [])

# --- Wait for ERPNext master data ---
print("Waiting for ERPNext master data (Company)...")
master_ready = False
for attempt in range(100):
    try:
        companies = api_get("Company", [["company_name", "=", "Wind Power LLC"]])
        if companies:
            print(f"  Master data ready after {attempt * 15}s")
            master_ready = True
            break
    except Exception:
        pass
    print(f"  Master data not ready yet... ({attempt * 15}s elapsed)", flush=True)
    time.sleep(15)

if not master_ready:
    print("ERROR: ERPNext master data not available after 10 minutes", file=sys.stderr)
    sys.exit(1)

# Re-login
session.post(f"{ERPNEXT_URL}/api/method/login", json={"usr": "Administrator", "pwd": "admin"})

# --- Ensure Items Exist ---
items_to_ensure = [
    {"item_code": "Advanced Wind Turbine", "item_name": "Advanced Wind Turbine",
     "item_group": "All Item Groups", "stock_uom": "Nos", "is_stock_item": 1,
     "description": "Next generation high-efficiency wind turbine"},
    {"item_code": "Shaft", "item_name": "Shaft",
     "item_group": "All Item Groups", "stock_uom": "Nos", "is_stock_item": 1},
    {"item_code": "Wing Sheet", "item_name": "Wing Sheet",
     "item_group": "All Item Groups", "stock_uom": "Nos", "is_stock_item": 1},
    {"item_code": "Base Plate", "item_name": "Base Plate",
     "item_group": "All Item Groups", "stock_uom": "Nos", "is_stock_item": 1}
]

for item in items_to_ensure:
    existing = api_get("Item", [["item_code", "=", item["item_code"]]])
    if not existing:
        r = session.post(f"{ERPNEXT_URL}/api/resource/Item", json=item)
        if r.status_code in (200, 201):
            print(f"  Created Item: {item['item_code']}")
        else:
            print(f"  ERROR creating Item {item['item_code']}: {r.text[:200]}", file=sys.stderr)
    else:
        print(f"  Found existing Item: {item['item_code']}")

# --- Clean up any pre-existing BOM for Advanced Wind Turbine to ensure clean slate ---
boms = api_get("BOM", [["item", "=", "Advanced Wind Turbine"]], limit=10)
for bom in boms:
    print(f"  Deleting pre-existing BOM: {bom['name']}")
    session.delete(f"{ERPNEXT_URL}/api/resource/BOM/{bom['name']}")

# --- Clean up target workstations / operations if they exist from previous runs ---
for ws in ["Assembly Station", "Testing Station"]:
    existing = api_get("Workstation", [["workstation_name", "=", ws]])
    if existing:
        session.delete(f"{ERPNEXT_URL}/api/resource/Workstation/{existing[0]['name']}")

for op in ["Mechanical Assembly", "Quality Testing"]:
    existing = api_get("Operation", [["operation", "=", op]])
    if existing:
        session.delete(f"{ERPNEXT_URL}/api/resource/Operation/{existing[0]['name']}")

print("Setup Complete")
PYEOF

echo "=== Task setup complete ==="