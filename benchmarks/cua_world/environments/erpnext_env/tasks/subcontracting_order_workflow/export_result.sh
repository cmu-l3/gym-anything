#!/bin/bash
# Export script for subcontracting_order_workflow task

echo "=== Exporting subcontracting_order_workflow results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

take_screenshot /tmp/subcontracting_final.png 2>/dev/null || true

python3 << 'PYEOF'
import requests, json, sys, os

ERPNEXT_URL = "http://localhost:8080"
session = requests.Session()

r = session.post(f"{ERPNEXT_URL}/api/method/login",
                 json={"usr": "Administrator", "pwd": "admin"})
if r.status_code != 200:
    print(f"ERROR: Login failed {r.status_code}", file=sys.stderr)
    sys.exit(1)

def api_get(doctype, filters=None, fields=None, limit=20):
    params = {"limit_page_length": limit}
    if filters:
        params["filters"] = json.dumps(filters)
    if fields:
        params["fields"] = json.dumps(fields)
    return session.get(f"{ERPNEXT_URL}/api/resource/{doctype}", params=params).json().get("data", [])

def get_doc(doctype, name):
    return session.get(f"{ERPNEXT_URL}/api/resource/{doctype}/{name}").json().get("data", {})

try:
    with open("/tmp/subcontracting_baseline.json") as f:
        baseline = json.load(f)
except Exception:
    baseline = {}

# Subcontracting Orders
scos = api_get("Subcontracting Order", [["supplier", "=", "Eagle Hardware"], ["docstatus", "=", 1]])
sco_details = []
for sco in scos:
    doc = get_doc("Subcontracting Order", sco["name"])
    sco_details.append(doc)

# Stock Entries (Send to Subcontractor)
ses = api_get("Stock Entry", [["stock_entry_type", "=", "Send to Subcontractor"], ["docstatus", "=", 1]])
se_details = []
for se in ses:
    doc = get_doc("Stock Entry", se["name"])
    se_details.append(doc)

# Subcontracting Receipts
scrs = api_get("Subcontracting Receipt", [["supplier", "=", "Eagle Hardware"], ["docstatus", "=", 1]])
scr_details = []
for scr in scrs:
    doc = get_doc("Subcontracting Receipt", scr["name"])
    scr_details.append(doc)

def get_stock(item_code, wh):
    b = api_get("Bin", [["item_code", "=", item_code], ["warehouse", "=", wh]], ["actual_qty"])
    return float(b[0]["actual_qty"]) if b else 0.0

stores_wh = baseline.get("stores_wh", "Stores - WP")
supplier_wh = baseline.get("supplier_wh", "Supplier - Eagle Hardware - WP")

stock_now = {
    "stores_base_plate_now": get_stock("Base Plate", stores_wh),
    "stores_wing_sheet_now": get_stock("Wing Sheet", stores_wh),
    "stores_frame_now": get_stock("Welded Turbine Frame", stores_wh),
    "supplier_base_plate_now": get_stock("Base Plate", supplier_wh),
    "supplier_wing_sheet_now": get_stock("Wing Sheet", supplier_wh)
}

task_start = 0
try:
    with open("/tmp/task_start_time.txt") as f:
        task_start = float(f.read().strip())
except:
    pass

result = {
    "baseline": baseline,
    "stock_now": stock_now,
    "subcontracting_orders": sco_details,
    "stock_entries": se_details,
    "subcontracting_receipts": scr_details,
    "task_start_time": task_start
}

with open("/tmp/subcontracting_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
print("\n=== Export complete ===")
PYEOF

echo "=== Export done ==="