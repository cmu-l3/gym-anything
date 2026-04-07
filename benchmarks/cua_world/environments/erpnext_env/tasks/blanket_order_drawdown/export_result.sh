#!/bin/bash
set -e
echo "=== Exporting blanket_order_drawdown results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
take_screenshot /tmp/blanket_order_drawdown_final.png 2>/dev/null || true

# Login and export
python3 << 'PYEOF'
import requests, json, sys, os

ERPNEXT_URL = "http://localhost:8080"
session = requests.Session()

r = session.post(f"{ERPNEXT_URL}/api/method/login", json={"usr": "Administrator", "pwd": "admin"})
if r.status_code != 200:
    print(f"ERROR: Login failed {r.status_code}", file=sys.stderr)
    sys.exit(1)

try:
    with open("/tmp/blanket_order_drawdown_baseline.json") as f:
        baseline = json.load(f)
except Exception:
    baseline = {"initial_bo_count": 0, "initial_po_count": 0}

task_start_time = 0
if os.path.exists("/tmp/task_start_time.txt"):
    try:
        with open("/tmp/task_start_time.txt") as f:
            task_start_time = int(f.read().strip())
    except:
        pass

def api_get(doctype, filters=None, fields=None, limit=100):
    params = {"limit_page_length": limit}
    if filters:
        params["filters"] = json.dumps(filters)
    if fields:
        params["fields"] = json.dumps(fields)
    try:
        return session.get(f"{ERPNEXT_URL}/api/resource/{doctype}", params=params).json().get("data", [])
    except:
        return []

def get_doc(doctype, name):
    try:
        return session.get(f"{ERPNEXT_URL}/api/resource/{doctype}/{name}").json().get("data", {})
    except:
        return {}

# Blanket Orders
bo_list = api_get("Blanket Order", 
                  [["supplier", "=", "Eagle Hardware"], ["docstatus", "=", 1]], 
                  fields=["name", "blanket_order_type", "supplier", "from_date", "to_date", "creation"])

bo_data = []
for bo in bo_list:
    doc = get_doc("Blanket Order", bo["name"])
    items = doc.get("items", [])
    items_data = []
    for itm in items:
        items_data.append({
            "item_code": itm.get("item_code"),
            "qty": float(itm.get("qty", 0)),
            "rate": float(itm.get("rate", 0)),
            "ordered_qty": float(itm.get("ordered_qty", 0))
        })
    bo_data.append({
        "name": bo["name"],
        "blanket_order_type": bo.get("blanket_order_type"),
        "supplier": bo.get("supplier"),
        "items": items_data
    })

# Purchase Orders
po_list = api_get("Purchase Order", 
                  [["supplier", "=", "Eagle Hardware"], ["docstatus", "=", 1]], 
                  fields=["name", "supplier", "creation", "grand_total"])

po_data = []
for po in po_list:
    doc = get_doc("Purchase Order", po["name"])
    items = doc.get("items", [])
    items_data = []
    for itm in items:
        items_data.append({
            "item_code": itm.get("item_code"),
            "qty": float(itm.get("qty", 0)),
            "rate": float(itm.get("rate", 0)),
            "blanket_order": itm.get("blanket_order"),
            "blanket_order_rate": float(itm.get("blanket_order_rate", 0))
        })
    po_data.append({
        "name": po["name"],
        "supplier": po.get("supplier"),
        "items": items_data
    })

result = {
    "task_start_time": task_start_time,
    "initial_bo_count": baseline.get("initial_bo_count", 0),
    "initial_po_count": baseline.get("initial_po_count", 0),
    "blanket_orders": bo_data,
    "purchase_orders": po_data
}

with open("/tmp/blanket_order_drawdown_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Export complete")
PYEOF

echo "=== Export done ==="