#!/bin/bash
# Export script for customer_credit_limit_resolution task
# Queries ERPNext for the original invoice status, payment entries, new sales orders, and credit limits.

echo "=== Exporting customer_credit_limit_resolution results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Capture final state screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

python3 << 'PYEOF'
import requests, json, sys, os

ERPNEXT_URL = "http://localhost:8080"
session = requests.Session()

r = session.post(f"{ERPNEXT_URL}/api/method/login",
                 json={"usr": "Administrator", "pwd": "admin"})
if r.status_code != 200:
    print(f"ERROR: Login failed {r.status_code}", file=sys.stderr)
    sys.exit(1)

try:
    with open("/tmp/customer_credit_limit_resolution_baseline.json") as f:
        baseline = json.load(f)
except Exception:
    baseline = {}

CUSTOMER = "Global Energy Partners"
original_si_name = baseline.get("original_si_name", "")

def api_get(doctype, filters=None, fields=None, limit=20):
    params = {"limit_page_length": limit}
    if filters:
        params["filters"] = json.dumps(filters)
    if fields:
        params["fields"] = json.dumps(fields)
    return session.get(f"{ERPNEXT_URL}/api/resource/{doctype}", params=params).json().get("data", [])

def get_doc(doctype, name):
    return session.get(f"{ERPNEXT_URL}/api/resource/{doctype}/{name}").json().get("data", {})

# 1. Original SI Status
original_si_doc = get_doc("Sales Invoice", original_si_name) if original_si_name else {}
si_status = {
    "name": original_si_name,
    "docstatus": original_si_doc.get("docstatus", 0),
    "outstanding_amount": original_si_doc.get("outstanding_amount", 9500.0),
    "status": original_si_doc.get("status", "Unknown")
}

# 2. Payment Entries for Customer
pe_list = api_get("Payment Entry", 
                  [["party", "=", CUSTOMER], ["docstatus", "=", 1]],
                  fields=["name", "paid_amount", "received_amount", "payment_type"])
pe_info = []
for pe in pe_list:
    doc = get_doc("Payment Entry", pe["name"])
    references = doc.get("references", [])
    linked_si = [ref.get("reference_name") for ref in references if ref.get("reference_doctype") == "Sales Invoice"]
    pe_info.append({
        "name": pe["name"],
        "paid_amount": pe.get("paid_amount", 0),
        "received_amount": pe.get("received_amount", 0),
        "payment_type": pe.get("payment_type"),
        "linked_invoices": linked_si
    })

# 3. New Sales Orders
so_list = api_get("Sales Order", 
                  [["customer", "=", CUSTOMER], ["docstatus", "=", 1]],
                  fields=["name", "grand_total"])
so_info = []
for so in so_list:
    doc = get_doc("Sales Order", so["name"])
    items = doc.get("items", [])
    has_awt = any(i.get("item_code") == "Advanced Wind Turbine" for i in items)
    awt_qty = sum(i.get("qty", 0) for i in items if i.get("item_code") == "Advanced Wind Turbine")
    so_info.append({
        "name": so["name"],
        "grand_total": so.get("grand_total", 0),
        "has_advanced_wind_turbine": has_awt,
        "awt_qty": awt_qty
    })

# 4. Customer Credit Limit Check
customer_doc = get_doc("Customer", CUSTOMER)
limits = customer_doc.get("credit_limits", [])
current_limit = limits[0].get("credit_limit", 0) if limits else 0
bypass_flag = limits[0].get("bypass_credit_limit_check", 0) if limits else 0

result = {
    "task_start_time": int(open("/tmp/task_start_time.txt").read().strip()) if os.path.exists("/tmp/task_start_time.txt") else 0,
    "original_si": si_status,
    "payment_entries": pe_info,
    "sales_orders": so_info,
    "credit_limit": current_limit,
    "bypass_flag": bypass_flag
}

with open("/tmp/customer_credit_limit_resolution_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
print("\n=== Export complete: /tmp/customer_credit_limit_resolution_result.json ===")
PYEOF

echo "=== Export done ==="