#!/bin/bash
# Export script for sales_fulfillment_cycle task
# Queries ERPNext for Delivery Note, Sales Invoice, and Payment Entry
# for Consumers and Consumers Express, writes to result JSON.

echo "=== Exporting sales_fulfillment_cycle results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

take_screenshot /tmp/sales_fulfillment_cycle_final.png 2>/dev/null || true

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
    with open("/tmp/sales_fulfillment_cycle_baseline.json") as f:
        baseline = json.load(f)
    so_name = baseline.get("so_name", "")
except Exception:
    so_name = ""

CUSTOMER = "Consumers and Consumers Express"

def api_get(doctype, filters=None, fields=None, limit=20):
    params = {"limit_page_length": limit}
    if filters:
        params["filters"] = json.dumps(filters)
    if fields:
        params["fields"] = json.dumps(fields)
    return session.get(f"{ERPNEXT_URL}/api/resource/{doctype}", params=params).json().get("data", [])

def get_doc(doctype, name):
    return session.get(f"{ERPNEXT_URL}/api/resource/{doctype}/{name}").json().get("data", {})

# --- Delivery Notes ---
dn_list = api_get("Delivery Note",
                   [["customer", "=", CUSTOMER], ["docstatus", "=", 1]],
                   fields=["name", "customer", "status", "grand_total"])
dn_info = []
for dn in dn_list:
    doc = get_doc("Delivery Note", dn["name"])
    items = doc.get("items", [])
    has_wt = any(i.get("item_code") == "Wind Turbine" for i in items)
    has_wm = any(i.get("item_code") == "Wind Mill A Series" for i in items)
    wt_qty = sum(i.get("qty", 0) for i in items if i.get("item_code") == "Wind Turbine")
    wm_qty = sum(i.get("qty", 0) for i in items if i.get("item_code") == "Wind Mill A Series")
    so_links = list({i.get("against_sales_order", "") for i in items})
    dn_info.append({
        "dn_name": dn["name"],
        "has_wind_turbine": has_wt,
        "has_wind_mill_a_series": has_wm,
        "wind_turbine_qty": wt_qty,
        "wind_mill_qty": wm_qty,
        "against_so": so_links,
        "grand_total": dn.get("grand_total", 0)
    })

# --- Sales Invoices ---
si_list = api_get("Sales Invoice",
                   [["customer", "=", CUSTOMER], ["docstatus", "=", 1],
                    ["is_return", "=", 0]],
                   fields=["name", "customer", "grand_total", "outstanding_amount", "status"])
si_info = []
for si in si_list:
    doc = get_doc("Sales Invoice", si["name"])
    items = doc.get("items", [])
    has_wt = any(i.get("item_code") == "Wind Turbine" for i in items)
    has_wm = any(i.get("item_code") == "Wind Mill A Series" for i in items)
    si_info.append({
        "si_name": si["name"],
        "grand_total": si.get("grand_total", 0),
        "outstanding_amount": si.get("outstanding_amount", 0),
        "has_wind_turbine": has_wt,
        "has_wind_mill_a_series": has_wm
    })

# --- Payment Entries ---
pe_list = api_get("Payment Entry",
                   [["party_type", "=", "Customer"],
                    ["party", "=", CUSTOMER],
                    ["docstatus", "=", 1]],
                   fields=["name", "party", "received_amount", "payment_type", "docstatus"])
pe_info = [{"pe_name": p["name"],
             "received_amount": p.get("received_amount", 0),
             "payment_type": p.get("payment_type", "")} for p in pe_list]

# Outstanding = sum of SI outstanding
total_outstanding = sum(si.get("outstanding_amount", 0) for si in si_info)

result = {
    "so_name": so_name,
    "customer": CUSTOMER,
    "delivery_notes": dn_info,
    "sales_invoices": si_info,
    "payment_entries": pe_info,
    "customer_outstanding": total_outstanding
}

with open("/tmp/sales_fulfillment_cycle_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
print("\n=== Export complete: /tmp/sales_fulfillment_cycle_result.json ===")
PYEOF

echo "=== Export done ==="
