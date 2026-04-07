#!/bin/bash
# Export script for fixed_asset_lifecycle task
# Queries ERPNext API for newly created Purchase Invoices, Assets, and Asset Movements.

echo "=== Exporting fixed_asset_lifecycle results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
take_screenshot /tmp/fixed_asset_lifecycle_final.png 2>/dev/null || true

python3 << 'PYEOF'
import requests, json, sys, time

ERPNEXT_URL = "http://localhost:8080"
session = requests.Session()

r = session.post(f"{ERPNEXT_URL}/api/method/login",
                 json={"usr": "Administrator", "pwd": "admin"})
if r.status_code != 200:
    print(f"ERROR: Login failed {r.status_code}", file=sys.stderr)
    sys.exit(1)

try:
    with open("/tmp/fixed_asset_lifecycle_baseline.json") as f:
        baseline = json.load(f)
except Exception:
    baseline = {"purchase_invoices": [], "assets": [], "asset_movements": []}

def api_get(doctype, filters=None, fields=None, limit=50):
    params = {"limit_page_length": limit}
    if filters:
        params["filters"] = json.dumps(filters)
    if fields:
        params["fields"] = json.dumps(fields)
    return session.get(f"{ERPNEXT_URL}/api/resource/{doctype}", params=params).json().get("data", [])

def get_doc(doctype, name):
    return session.get(f"{ERPNEXT_URL}/api/resource/{doctype}/{name}").json().get("data", {})

# --- 1. Purchase Invoices ---
pi_list = api_get("Purchase Invoice",
                   [["supplier", "=", "Eagle Hardware"], ["docstatus", "=", 1]],
                   fields=["name", "grand_total", "docstatus"])
new_pis = []
for pi in pi_list:
    if pi["name"] not in baseline.get("purchase_invoices", []):
        doc = get_doc("Purchase Invoice", pi["name"])
        has_cnc = any(i.get("item_code") == "CNC Milling Machine" for i in doc.get("items", []))
        if has_cnc:
            new_pis.append({
                "name": pi["name"],
                "grand_total": pi.get("grand_total", 0),
                "items": [i.get("item_code") for i in doc.get("items", [])]
            })

# --- 2. Assets ---
asset_list = api_get("Asset",
                      [["item_code", "=", "CNC Milling Machine"]],
                      fields=["name", "docstatus", "location", "gross_purchase_amount", "status"])
new_assets = []
for ast in asset_list:
    if ast["name"] not in baseline.get("assets", []):
        doc = get_doc("Asset", ast["name"])
        schedules = doc.get("schedules", [])
        new_assets.append({
            "name": ast["name"],
            "docstatus": ast.get("docstatus", 0),
            "status": ast.get("status", ""),
            "location": ast.get("location", ""),
            "gross_purchase_amount": ast.get("gross_purchase_amount", 0),
            "depreciation_schedule_rows": len(schedules),
            "depreciation_method": doc.get("finance_books", [{}])[0].get("depreciation_method", "") if doc.get("finance_books") else ""
        })

# --- 3. Asset Movements ---
movement_list = api_get("Asset Movement",
                         [["purpose", "=", "Transfer"], ["docstatus", "=", 1]],
                         fields=["name", "purpose", "docstatus"])
new_movements = []
for mv in movement_list:
    if mv["name"] not in baseline.get("asset_movements", []):
        doc = get_doc("Asset Movement", mv["name"])
        assets = doc.get("assets", [])
        cnc_moved = False
        target = ""
        for a in assets:
            # Check if this movement targets the CNC asset
            if any(na["name"] == a.get("asset") for na in new_assets):
                cnc_moved = True
                target = a.get("target_location", "")
                break
        
        if cnc_moved:
            new_movements.append({
                "name": mv["name"],
                "purpose": doc.get("purpose", ""),
                "target_location": target
            })

result = {
    "purchase_invoices": new_pis,
    "assets": new_assets,
    "asset_movements": new_movements,
    "export_timestamp": time.time()
}

with open("/tmp/fixed_asset_lifecycle_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
print("\n=== Export complete: /tmp/fixed_asset_lifecycle_result.json ===")
PYEOF

echo "=== Export done ==="