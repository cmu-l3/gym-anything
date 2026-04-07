#!/bin/bash
# Export script for full_procurement_cycle task
# Queries ERPNext API for PR, PI, and Payment Entry linked to Eagle Hardware
# and writes results to /tmp/full_procurement_cycle_result.json

echo "=== Exporting full_procurement_cycle results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
take_screenshot /tmp/full_procurement_cycle_final.png 2>/dev/null || true

python3 << 'PYEOF'
import requests, json, sys

ERPNEXT_URL = "http://localhost:8080"
session = requests.Session()

r = session.post(f"{ERPNEXT_URL}/api/method/login",
                 json={"usr": "Administrator", "pwd": "admin"})
if r.status_code != 200:
    print(f"ERROR: Login failed {r.status_code}", file=sys.stderr)
    sys.exit(1)

# Load baseline to get PO name
try:
    with open("/tmp/full_procurement_cycle_baseline.json") as f:
        baseline = json.load(f)
    po_name = baseline.get("po_name", "")
except Exception:
    po_name = ""

def api_get(doctype, filters=None, fields=None, limit=20):
    params = {"limit_page_length": limit}
    if filters:
        params["filters"] = json.dumps(filters)
    if fields:
        params["fields"] = json.dumps(fields)
    resp = session.get(f"{ERPNEXT_URL}/api/resource/{doctype}", params=params)
    return resp.json().get("data", [])

def get_doc(doctype, name):
    resp = session.get(f"{ERPNEXT_URL}/api/resource/{doctype}/{name}")
    return resp.json().get("data", {})

# --- Purchase Receipts for Eagle Hardware (submitted) ---
pr_list = api_get("Purchase Receipt",
                   [["supplier", "=", "Eagle Hardware"], ["docstatus", "=", 1]],
                   fields=["name", "supplier", "status", "docstatus", "purchase_order"])

# Filter PRs linked to our specific PO
pr_linked = []
pr_items_info = []
for pr in pr_list:
    doc = get_doc("Purchase Receipt", pr["name"])
    items = doc.get("items", [])
    for itm in items:
        if (itm.get("purchase_order") == po_name or po_name == "") and \
           itm.get("item_code") == "Upper Bearing Plate":
            pr_linked.append(pr["name"])
            pr_items_info.append({
                "pr_name": pr["name"],
                "item_code": itm.get("item_code"),
                "qty": itm.get("qty", 0),
                "purchase_order": itm.get("purchase_order", "")
            })
            break

# --- Purchase Invoices for Eagle Hardware (submitted) ---
pi_list = api_get("Purchase Invoice",
                   [["supplier", "=", "Eagle Hardware"], ["docstatus", "=", 1]],
                   fields=["name", "supplier", "grand_total", "outstanding_amount",
                            "docstatus", "status"])

pi_info = []
for pi in pi_list:
    doc = get_doc("Purchase Invoice", pi["name"])
    items = doc.get("items", [])
    has_ubp = any(itm.get("item_code") == "Upper Bearing Plate" for itm in items)
    if has_ubp:
        pi_info.append({
            "pi_name": pi["name"],
            "grand_total": pi.get("grand_total", 0),
            "outstanding_amount": pi.get("outstanding_amount", 0),
            "status": pi.get("status", "")
        })

# --- Payment Entries for Eagle Hardware ---
pe_list = api_get("Payment Entry",
                   [["party_type", "=", "Supplier"],
                    ["party", "=", "Eagle Hardware"],
                    ["docstatus", "=", 1]],
                   fields=["name", "party", "paid_amount", "payment_type",
                            "docstatus", "posting_date"])

pe_info = []
for pe in pe_list:
    pe_info.append({
        "pe_name": pe["name"],
        "paid_amount": pe.get("paid_amount", 0),
        "payment_type": pe.get("payment_type", "")
    })

# --- Check Eagle Hardware outstanding via Party Account ---
eagle_outstanding = None
try:
    resp = session.get(f"{ERPNEXT_URL}/api/method/frappe.client.get_value",
                       params={"doctype": "Supplier",
                               "filters": json.dumps({"name": "Eagle Hardware"}),
                               "fieldname": "name"})
    # Outstanding is sum of PI outstanding_amount
    total_outstanding = sum(p["outstanding_amount"] for p in pi_info)
    eagle_outstanding = total_outstanding
except Exception:
    eagle_outstanding = None

result = {
    "po_name": po_name,
    "supplier": "Eagle Hardware",
    "purchase_receipts": pr_linked,
    "pr_items": pr_items_info,
    "purchase_invoices": pi_info,
    "payment_entries": pe_info,
    "eagle_outstanding": eagle_outstanding
}

with open("/tmp/full_procurement_cycle_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
print("\n=== Export complete: /tmp/full_procurement_cycle_result.json ===")
PYEOF

echo "=== Export done ==="
