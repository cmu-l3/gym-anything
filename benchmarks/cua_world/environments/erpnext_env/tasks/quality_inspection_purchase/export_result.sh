#!/bin/bash
# Export script for quality_inspection_purchase task
# Queries ERPNext API for QI Template, Item Config, QI, PR, and Stock Bin.

echo "=== Exporting quality_inspection_purchase results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
DISPLAY=:1 scrot /tmp/quality_inspection_purchase_final.png 2>/dev/null || true

python3 << 'PYEOF'
import requests, json, sys, os

ERPNEXT_URL = "http://localhost:8080"
session = requests.Session()

# Login
r = session.post(f"{ERPNEXT_URL}/api/method/login",
                 json={"usr": "Administrator", "pwd": "admin"})
if r.status_code != 200:
    print(f"ERROR: Login failed {r.status_code}", file=sys.stderr)
    sys.exit(1)

# Load baseline
baseline = {}
if os.path.exists("/tmp/quality_inspection_purchase_baseline.json"):
    with open("/tmp/quality_inspection_purchase_baseline.json", "r") as f:
        baseline = json.load(f)

po_name = baseline.get("po_name", "")
item_code = baseline.get("item_code", "Shaft")
supplier = baseline.get("supplier", "Eagle Hardware")
target_warehouse = baseline.get("target_warehouse", "Stores - WP")
initial_stock = baseline.get("initial_stock", 0.0)

def api_get(doctype, filters=None, fields=None):
    params = {"limit_page_length": 50}
    if filters:
        params["filters"] = json.dumps(filters)
    if fields:
        params["fields"] = json.dumps(fields)
    try:
        resp = session.get(f"{ERPNEXT_URL}/api/resource/{doctype}", params=params)
        return resp.json().get("data", [])
    except Exception:
        return []

def get_doc(doctype, name):
    try:
        resp = session.get(f"{ERPNEXT_URL}/api/resource/{doctype}/{name}")
        return resp.json().get("data", {})
    except Exception:
        return {}

# --- 1. Quality Inspection Template ---
qi_template_name = "Shaft Incoming QC"
qi_template_doc = get_doc("Quality Inspection Template", qi_template_name)
qi_parameters = []
if qi_template_doc:
    # Field could be named 'item_quality_inspection_parameter'
    children = qi_template_doc.get("item_quality_inspection_parameter", [])
    for p in children:
        qi_parameters.append({
            "specification": p.get("specification", ""),
            "min_value": float(p.get("min_value", 0.0)),
            "max_value": float(p.get("max_value", 0.0)),
            "numeric": p.get("numeric", 0)
        })

qi_template_info = {
    "exists": bool(qi_template_doc),
    "name": qi_template_doc.get("name"),
    "parameters": qi_parameters,
    "parameter_count": len(qi_parameters)
}

# --- 2. Item Configuration ---
item_doc = get_doc("Item", item_code)
item_info = {
    "item_code": item_code,
    "inspection_required_before_purchase": item_doc.get("inspection_required_before_purchase", 0),
    "quality_inspection_template": item_doc.get("quality_inspection_template", "")
}

# --- 3. Quality Inspections ---
qi_list = api_get("Quality Inspection",
                  [["item_code", "=", item_code], ["docstatus", "=", 1]],
                  fields=["name", "inspection_type", "status", "reference_type", "reference_name", "docstatus"])

# --- 4. Purchase Receipts ---
pr_list = api_get("Purchase Receipt",
                  [["supplier", "=", supplier], ["docstatus", "=", 1]],
                  fields=["name", "supplier", "docstatus", "status"])

pr_items_info = []
for pr in pr_list:
    doc = get_doc("Purchase Receipt", pr["name"])
    items = doc.get("items", [])
    for itm in items:
        if itm.get("item_code") == item_code and \
           (not po_name or itm.get("purchase_order") == po_name):
            pr_items_info.append({
                "pr_name": pr["name"],
                "item_code": itm.get("item_code"),
                "qty": float(itm.get("qty", 0.0)),
                "purchase_order": itm.get("purchase_order", ""),
                "quality_inspection": itm.get("quality_inspection", "")
            })

# --- 5. Current Stock Level ---
bin_records = api_get("Bin", [["item_code", "=", item_code], ["warehouse", "=", target_warehouse]], ["actual_qty"])
current_stock = float(bin_records[0].get("actual_qty", 0.0)) if bin_records else 0.0
stock_increase = current_stock - initial_stock

result = {
    "baseline": baseline,
    "qi_template": qi_template_info,
    "item_configuration": item_info,
    "quality_inspections": qi_list,
    "purchase_receipts": pr_items_info,
    "stock_info": {
        "warehouse": target_warehouse,
        "initial_stock": initial_stock,
        "current_stock": current_stock,
        "stock_increase": stock_increase
    }
}

with open("/tmp/quality_inspection_purchase_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
print("\n=== Export complete ===")
PYEOF