#!/bin/bash
# Export script for deferred_revenue_accounting task
# Queries ERPNext for the configured Item, Sales Invoice, Process Deferred Accounting document,
# and GL entries, then writes to /tmp/deferred_revenue_accounting_result.json.

echo "=== Exporting deferred_revenue_accounting results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
take_screenshot /tmp/deferred_revenue_accounting_final.png 2>/dev/null || true

python3 << 'PYEOF'
import requests, json, sys

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

# 1. Item checks
items = api_get("Item", [["item_name", "like", "%Annual Maintenance%"]], fields=["name"])
item_info = []
for i in items:
    doc = get_doc("Item", i["name"])
    item_info.append({
        "name": doc.get("name"),
        "is_stock_item": doc.get("is_stock_item"),
        "enable_deferred_revenue": doc.get("enable_deferred_revenue"),
        "deferred_revenue_account": doc.get("deferred_revenue_account"),
        "no_of_months": doc.get("no_of_months")
    })

# 2. Sales Invoices
si_list = api_get("Sales Invoice", [["customer", "=", "Green Energy Corp"], ["docstatus", "=", 1]], fields=["name", "grand_total", "posting_date"])
si_info = []
for si in si_list:
    doc = get_doc("Sales Invoice", si["name"])
    items_in_si = doc.get("items", [])
    for itm in items_in_si:
        if "Maintenance" in itm.get("item_name", "") or "Maintenance" in itm.get("item_code", ""):
            si_info.append({
                "si_name": si["name"],
                "grand_total": doc.get("grand_total"),
                "posting_date": doc.get("posting_date"),
                "enable_deferred_revenue": itm.get("enable_deferred_revenue"),
                "service_start_date": itm.get("service_start_date"),
                "service_end_date": itm.get("service_end_date"),
                "base_net_amount": itm.get("base_net_amount")
            })

# 3. Process Deferred Accounting
pda_list = api_get("Process Deferred Accounting", [["docstatus", "=", 1]], fields=["name", "type", "start_date", "end_date", "posting_date"])

# 4. GL Entries (Journal Entries hitting the Liability account)
gl_list = api_get("GL Entry", [["account", "like", "%Deferred Revenue%"], ["voucher_type", "=", "Journal Entry"]], fields=["name", "voucher_no", "account", "debit", "credit", "posting_date", "against_voucher"])

result = {
    "item_info": item_info,
    "sales_invoices": si_info,
    "process_deferred_accounting": pda_list,
    "gl_entries": gl_list
}

with open("/tmp/deferred_revenue_accounting_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
print("\n=== Export complete: /tmp/deferred_revenue_accounting_result.json ===")
PYEOF

echo "=== Export done ==="