#!/bin/bash
# Setup script for quality_inspection_purchase task
# Creates Eagle Hardware supplier, verifies Shaft item, creates a Purchase Order for 30 Shafts,
# and captures the baseline stock level.

set -e
echo "=== Setting up quality_inspection_purchase ==="

# Source utilities if available
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt

echo "Waiting for ERPNext to be fully ready..."
# Simple wait loop for ERPNext availability
for attempt in {1..60}; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/api/method/version 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ]; then
        break
    fi
    sleep 5
done

python3 << 'PYEOF'
import requests, json, sys, time
from datetime import date, timedelta

ERPNEXT_URL = "http://localhost:8080"
session = requests.Session()

r = session.post(f"{ERPNEXT_URL}/api/method/login",
                 json={"usr": "Administrator", "pwd": "admin"})
if r.status_code != 200:
    print(f"ERROR: Login failed {r.status_code}", file=sys.stderr)
    sys.exit(1)
print("Logged in successfully to ERPNext API")

def api_get(doctype, filters=None, fields=None, limit=50):
    params = {"limit_page_length": limit}
    if filters:
        params["filters"] = json.dumps(filters)
    if fields:
        params["fields"] = json.dumps(fields)
    try:
        resp = session.get(f"{ERPNEXT_URL}/api/resource/{doctype}", params=params)
        return resp.json().get("data", [])
    except Exception:
        return []

# --- Wait for ERPNext master data (Company, Warehouses) ---
print("Waiting for ERPNext master data...")
master_ready = False
for attempt in range(40):  # up to 10 minutes
    companies = api_get("Company", [["company_name", "=", "Wind Power LLC"]])
    warehouses = api_get("Warehouse", [["warehouse_name", "=", "Stores"]])
    if companies and warehouses:
        master_ready = True
        break
    time.sleep(15)

if not master_ready:
    print("ERROR: Master data not available.", file=sys.stderr)
    sys.exit(1)

# --- Ensure Supplier ---
supplier_name = "Eagle Hardware"
print(f"Ensuring Supplier: {supplier_name}")
existing_supplier = api_get("Supplier", [["supplier_name", "=", supplier_name]])
if not existing_supplier:
    session.post(f"{ERPNEXT_URL}/api/resource/Supplier", json={
        "supplier_name": supplier_name,
        "supplier_type": "Company",
        "supplier_group": "All Supplier Groups"
    })

# --- Ensure Item "Shaft" ---
item_code = "Shaft"
print(f"Ensuring Item: {item_code}")
existing_item = api_get("Item", [["item_code", "=", item_code]])
if not existing_item:
    session.post(f"{ERPNEXT_URL}/api/resource/Item", json={
        "item_code": item_code,
        "item_name": item_code,
        "item_group": "Raw Material",
        "stock_uom": "Nos",
        "is_stock_item": 1,
        "description": "1.25 in. Diameter x 6 ft. Mild Steel Tubing",
        "standard_buying_price": 50.0
    })
else:
    # Ensure inspection is NOT already required to give agent a clean slate
    session.put(f"{ERPNEXT_URL}/api/resource/Item/{item_code}", json={
        "inspection_required_before_purchase": 0,
        "quality_inspection_template": ""
    })

# --- Determine Warehouse ---
wh_list = api_get("Warehouse", [["warehouse_name", "=", "Stores"]])
target_warehouse = wh_list[0]["name"] if wh_list else "Stores - WP"
print(f"Target warehouse: {target_warehouse}")

# --- Get Baseline Stock ---
bin_records = api_get("Bin", [["item_code", "=", item_code], ["warehouse", "=", target_warehouse]], ["actual_qty"])
initial_stock = float(bin_records[0].get("actual_qty", 0.0)) if bin_records else 0.0
print(f"Baseline stock for {item_code}: {initial_stock}")

# --- Create Purchase Order ---
print("Creating Purchase Order...")
po_name = ""
qty_to_order = 30
today = str(date.today())
schedule_date = str(date.today() + timedelta(days=2))

r_po = session.post(f"{ERPNEXT_URL}/api/resource/Purchase Order", json={
    "supplier": supplier_name,
    "transaction_date": today,
    "schedule_date": schedule_date,
    "items": [{
        "item_code": item_code,
        "qty": qty_to_order,
        "rate": 50.0,
        "schedule_date": schedule_date
    }]
})

if r_po.status_code in (200, 201):
    po_data = r_po.json().get("data", {})
    po_name = po_data.get("name")
    print(f"Created PO: {po_name}")
    
    # Submit PO
    time.sleep(1)
    doc_to_submit = session.get(f"{ERPNEXT_URL}/api/resource/Purchase Order/{po_name}").json().get("data")
    r_sub = session.post(f"{ERPNEXT_URL}/api/method/frappe.client.submit", json={"doc": doc_to_submit})
    if r_sub.status_code == 200:
        print(f"Submitted PO: {po_name}")
    else:
        print(f"ERROR submitting PO: {r_sub.text}", file=sys.stderr)
else:
    print(f"ERROR creating PO: {r_po.text}", file=sys.stderr)

# --- Save Baseline Data ---
baseline_data = {
    "po_name": po_name,
    "item_code": item_code,
    "supplier": supplier_name,
    "target_warehouse": target_warehouse,
    "initial_stock": initial_stock,
    "expected_qty": qty_to_order
}

with open("/tmp/quality_inspection_purchase_baseline.json", "w") as f:
    json.dump(baseline_data, f, indent=2)

PYEOF

# Navigate browser to Quality Inspection Template list to assist agent start
echo "Navigating browser to Quality Inspection Template..."
DISPLAY=:1 xdotool key ctrl+l || true
sleep 0.5
DISPLAY=:1 xdotool type --clearmodifiers "http://localhost:8080/app/quality-inspection-template" || true
sleep 0.5
DISPLAY=:1 xdotool key Return || true
sleep 3

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="