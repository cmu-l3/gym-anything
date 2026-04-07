#!/bin/bash
# Export script for drop_shipping_workflow_execution task
# Queries ERPNext for new Sales Orders, Purchase Orders, and Delivery Notes.
# Writes results to /tmp/drop_shipping_workflow_execution_result.json

echo "=== Exporting drop_shipping_workflow_execution results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

take_screenshot /tmp/drop_shipping_workflow_execution_final.png 2>/dev/null || true

python3 << 'PYEOF'
import requests, json, sys

ERPNEXT_URL = "http://localhost:8080"
session = requests.Session()

r = session.post(f"{ERPNEXT_URL}/api/method/login",
                 json={"usr": "Administrator", "pwd": "admin"})
if r.status_code != 200:
    print(f"ERROR: Login failed {r.status_code}", file=sys.stderr)
    sys.exit(1)

try:
    with open("/tmp/drop_shipping_workflow_baseline.json") as f:
        baseline = json.load(f)
except Exception:
    baseline = {}

existing_so = set(baseline.get("existing_so", []))
existing_po = set(baseline.get("existing_po", []))
existing_dn = set(baseline.get("existing_dn", []))

def api_get(doctype, filters=None, fields=None, limit=50):
    params = {"limit_page_length": limit}
    if filters:
        params["filters"] = json.dumps(filters)
    if fields:
        params["fields"] = json.dumps(fields)
    return session.get(f"{ERPNEXT_URL}/api/resource/{doctype}", params=params).json().get("data", [])

def get_doc(doctype, name):
    return session.get(f"{ERPNEXT_URL}/api/resource/{doctype}/{name}").json().get("data", {})

# 1. Sales Orders (Drop Ship config check)
all_so = api_get("Sales Order",
                 [["customer", "=", "Apex Corp"], ["docstatus", "=", 1]],
                 fields=["name", "docstatus"])
new_so = [s for s in all_so if s["name"] not in existing_so]

so_details = []
for so in new_so:
    doc = get_doc("Sales Order", so["name"])
    items = doc.get("items", [])
    has_item = False
    drop_ship_flag = False
    supplier = ""
    for item in items:
        if item.get("item_code") == "Industrial Solar Inverter":
            has_item = True
            if item.get("delivered_by_supplier") in (1, "1", True):
                drop_ship_flag = True
                supplier = item.get("supplier", "")
            break
    
    so_details.append({
        "so_name": so["name"],
        "has_item": has_item,
        "delivered_by_supplier": drop_ship_flag,
        "supplier": supplier
    })

# 2. Purchase Orders
all_po = api_get("Purchase Order",
                 [["supplier", "=", "Global Solar Supply"], ["docstatus", "=", 1]],
                 fields=["name", "docstatus"])
new_po = [p for p in all_po if p["name"] not in existing_po]

po_details = []
for po in new_po:
    doc = get_doc("Purchase Order", po["name"])
    items = doc.get("items", [])
    linked_so = []
    has_item = False
    for item in items:
        if item.get("item_code") == "Industrial Solar Inverter":
            has_item = True
            if item.get("sales_order"):
                linked_so.append(item.get("sales_order"))
    
    po_details.append({
        "po_name": po["name"],
        "has_item": has_item,
        "linked_to_so": linked_so
    })

# 3. Delivery Notes (In Drop Ship, DN is linked to PO/SO)
all_dn = api_get("Delivery Note",
                 [["customer", "=", "Apex Corp"], ["docstatus", "=", 1]],
                 fields=["name", "docstatus"])
new_dn = [d for d in all_dn if d["name"] not in existing_dn]

dn_details = []
for dn in new_dn:
    doc = get_doc("Delivery Note", dn["name"])
    items = doc.get("items", [])
    has_item = False
    linked_so = []
    linked_po = []
    for item in items:
        if item.get("item_code") == "Industrial Solar Inverter":
            has_item = True
            if item.get("against_sales_order"):
                linked_so.append(item.get("against_sales_order"))
            if item.get("purchase_order"):
                linked_po.append(item.get("purchase_order"))
    
    dn_details.append({
        "dn_name": dn["name"],
        "has_item": has_item,
        "linked_to_so": linked_so,
        "linked_to_po": linked_po
    })

# 4. Inventory check (Bins should show 0 actual qty in local warehouses)
bins = api_get("Bin", [["item_code", "=", "Industrial Solar Inverter"]], fields=["warehouse", "actual_qty"])
local_inventory = sum(float(b.get("actual_qty", 0)) for b in bins if b.get("actual_qty"))

result = {
    "sales_orders": so_details,
    "purchase_orders": po_details,
    "delivery_notes": dn_details,
    "local_inventory": local_inventory
}

with open("/tmp/drop_shipping_workflow_execution_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
print("\n=== Export complete ===")
PYEOF

echo "=== Export done ==="