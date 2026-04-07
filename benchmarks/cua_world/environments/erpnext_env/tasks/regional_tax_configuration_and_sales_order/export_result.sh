#!/bin/bash
# Export script for regional_tax_configuration_and_sales_order task
# Queries ERPNext API for created accounts, templates, and Sales Orders.

echo "=== Exporting regional_tax_configuration_and_sales_order results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
take_screenshot /tmp/regional_tax_final.png 2>/dev/null || true

python3 << 'PYEOF'
import requests, json, sys, time

ERPNEXT_URL = "http://localhost:8080"
session = requests.Session()

# --- Login ---
r = session.post(f"{ERPNEXT_URL}/api/method/login",
                 json={"usr": "Administrator", "pwd": "admin"})
if r.status_code != 200:
    print(f"ERROR: Login failed {r.status_code}", file=sys.stderr)
    sys.exit(1)

# Load baseline
try:
    with open("/tmp/regional_tax_baseline.json") as f:
        baseline = json.load(f)
except Exception:
    baseline = {"task_start_time": 0}

task_start_time = baseline.get("task_start_time", 0)

def api_get(doctype, filters=None, fields=None):
    params = {"limit_page_length": 50}
    if filters:
        params["filters"] = json.dumps(filters)
    if fields:
        params["fields"] = json.dumps(fields)
    resp = session.get(f"{ERPNEXT_URL}/api/resource/{doctype}", params=params)
    return resp.json().get("data", [])

def get_doc(doctype, name):
    resp = session.get(f"{ERPNEXT_URL}/api/resource/{doctype}/{name}")
    return resp.json().get("data", {})

# 1. Fetch Tax Accounts
all_accounts = api_get("Account", [["company", "=", "Wind Power LLC"]], 
                       fields=["name", "account_name", "parent_account", "account_type", "creation"])
tax_accounts = []
for acc in all_accounts:
    name_lower = acc.get("account_name", "").lower()
    if "gst" in name_lower or "pst" in name_lower:
        tax_accounts.append(acc)

# 2. Fetch Sales Taxes and Charges Templates
templates = api_get("Sales Taxes and Charges Template", 
                    fields=["name", "title", "company", "creation"])
bc_templates = []
for tmpl in templates:
    if "british" in tmpl.get("title", "").lower() or "bc" in tmpl.get("title", "").lower():
        doc = get_doc("Sales Taxes and Charges Template", tmpl["name"])
        bc_templates.append({
            "name": tmpl["name"],
            "title": tmpl["title"],
            "creation": tmpl["creation"],
            "taxes": doc.get("taxes", [])
        })

# 3. Fetch Sales Orders for Maple Leaf Wind
sales_orders = api_get("Sales Order", 
                       [["customer", "=", "Maple Leaf Wind"]],
                       fields=["name", "customer", "docstatus", "net_total", 
                               "total_taxes_and_charges", "grand_total", 
                               "taxes_and_charges", "creation"])
so_details = []
for so in sales_orders:
    doc = get_doc("Sales Order", so["name"])
    items = [{"item_code": i.get("item_code"), "qty": i.get("qty"), "rate": i.get("rate")} for i in doc.get("items", [])]
    taxes = [{"account_head": t.get("account_head"), "rate": t.get("rate"), "tax_amount": t.get("tax_amount")} for t in doc.get("taxes", [])]
    
    so_details.append({
        "name": so["name"],
        "docstatus": so["docstatus"],
        "net_total": so["net_total"],
        "total_taxes_and_charges": so["total_taxes_and_charges"],
        "grand_total": so["grand_total"],
        "taxes_and_charges_template": so.get("taxes_and_charges"),
        "creation": so["creation"],
        "items": items,
        "applied_taxes": taxes
    })

# Construct result payload
result = {
    "task_start_time": task_start_time,
    "found_tax_accounts": tax_accounts,
    "found_tax_templates": bc_templates,
    "sales_orders": so_details
}

with open("/tmp/regional_tax_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
print("\n=== Export complete: /tmp/regional_tax_result.json ===")
PYEOF

echo "=== Export done ==="