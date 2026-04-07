#!/bin/bash
echo "=== Exporting warehouse_putaway_rule_receipt results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

take_screenshot /tmp/warehouse_putaway_rule_receipt_final.png 2>/dev/null || true

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
    with open("/tmp/warehouse_putaway_rule_receipt_baseline.json") as f:
        baseline = json.load(f)
    po_name = baseline.get("po_name", "")
except Exception:
    po_name = ""

def api_get(doctype, filters=None, fields=None, limit=50):
    params = {"limit_page_length": limit}
    if filters:
        params["filters"] = json.dumps(filters)
    if fields:
        params["fields"] = json.dumps(fields)
    return session.get(f"{ERPNEXT_URL}/api/resource/{doctype}", params=params).json().get("data", [])

def get_doc(doctype, name):
    return session.get(f"{ERPNEXT_URL}/api/resource/{doctype}/{name}").json().get("data", {})

# 1. Putaway Rules
rules = api_get("Putaway Rule", fields=["name", "item_code", "warehouse", "capacity", "priority", "company"])
putaway_rules = []
for rule in rules:
    putaway_rules.append({
        "name": rule.get("name"),
        "item_code": rule.get("item_code"),
        "warehouse": rule.get("warehouse"),
        "capacity": rule.get("capacity"),
        "priority": rule.get("priority")
    })

# 2. Purchase Receipts linked to the PO
pr_list = api_get("Purchase Receipt",
                   [["supplier", "=", "Eagle Hardware"], ["docstatus", "=", 1]],
                   fields=["name", "supplier", "docstatus", "apply_putaway_rule"])

pr_details = []
for pr in pr_list:
    doc = get_doc("Purchase Receipt", pr["name"])
    items = doc.get("items", [])
    linked_to_po = False
    for itm in items:
        if itm.get("purchase_order") == po_name or not po_name:
            linked_to_po = True
            break
    if linked_to_po:
        pr_details.append({
            "name": pr["name"],
            "apply_putaway_rule": doc.get("apply_putaway_rule", 0),
            "items": [{"item_code": i.get("item_code"), "qty": i.get("qty"), "warehouse": i.get("warehouse")} for i in items]
        })

# 3. Stock Ledger Entries (SLEs) to verify actual stock in warehouses
sles = api_get("Stock Ledger Entry", 
                [["voucher_type", "=", "Purchase Receipt"]],
                fields=["item_code", "warehouse", "actual_qty", "voucher_no"])

stock_movements = []
for sle in sles:
    if any(pr["name"] == sle.get("voucher_no") for pr in pr_details):
        stock_movements.append({
            "item_code": sle.get("item_code"),
            "warehouse": sle.get("warehouse"),
            "qty": sle.get("actual_qty"),
            "voucher_no": sle.get("voucher_no")
        })

# Summarize stock by warehouse
stock_summary = {
    "Blade Rack 1 - WP": 0,
    "Blade Rack 2 - WP": 0,
    "Heavy Parts - WP": 0
}
for movement in stock_movements:
    wh = movement.get("warehouse")
    if wh in stock_summary and movement.get("item_code") == "Rotor Blade":
        stock_summary[wh] += float(movement.get("qty", 0))
    elif wh == "Heavy Parts - WP" and movement.get("item_code") == "Gearbox":
        stock_summary[wh] += float(movement.get("qty", 0))

result = {
    "po_name": po_name,
    "putaway_rules": putaway_rules,
    "purchase_receipts": pr_details,
    "stock_movements": stock_movements,
    "stock_summary": stock_summary
}

with open("/tmp/warehouse_putaway_rule_receipt_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
print("\n=== Export complete ===")
PYEOF