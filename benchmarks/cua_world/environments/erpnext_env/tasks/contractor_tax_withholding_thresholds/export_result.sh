#!/bin/bash
# Export script for contractor_tax_withholding_thresholds task
# Queries ERPNext for Tax Withholding Category, Supplier, Purchase Invoices, and GL Entries.

echo "=== Exporting contractor_tax_withholding_thresholds results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

take_screenshot /tmp/contractor_tax_final.png 2>/dev/null || true

python3 << 'PYEOF'
import requests, json, sys, os

ERPNEXT_URL = "http://localhost:8080"
session = requests.Session()

r = session.post(f"{ERPNEXT_URL}/api/method/login",
                 json={"usr": "Administrator", "pwd": "admin"})
if r.status_code != 200:
    print(f"ERROR: Login failed {r.status_code}", file=sys.stderr)
    sys.exit(1)

def api_get(doctype, filters=None, fields=None, limit=50):
    params = {"limit_page_length": limit}
    if filters:
        params["filters"] = json.dumps(filters)
    if fields:
        params["fields"] = json.dumps(fields)
    return session.get(f"{ERPNEXT_URL}/api/resource/{doctype}", params=params).json().get("data", [])

def get_doc(doctype, name):
    return session.get(f"{ERPNEXT_URL}/api/resource/{doctype}/{name}").json().get("data", {})

try:
    with open("/tmp/task_start_time.txt", "r") as f:
        task_start = int(f.read().strip())
except Exception:
    task_start = 0

# --- 1. Tax Withholding Category ---
categories = api_get("Tax Withholding Category")
cat_details = []
for c in categories:
    doc = get_doc("Tax Withholding Category", c["name"])
    rates = doc.get("rates", [])
    accounts = doc.get("accounts", [])
    cat_details.append({
        "name": c["name"],
        "rates": [{"tax_withholding_rate": r.get("tax_withholding_rate"),
                   "single_transaction_threshold": r.get("single_transaction_threshold")} for r in rates],
        "accounts": [{"company": a.get("company"),
                      "account": a.get("account")} for a in accounts]
    })

# --- 2. Supplier Linkage ---
supplier = get_doc("Supplier", "Build-It Construction")
supplier_tax_category = supplier.get("tax_withholding_category", "")

# --- 3. Purchase Invoices ---
# Fetch all PIs for the supplier submitted after setup
pis = api_get("Purchase Invoice",
              [["supplier", "=", "Build-It Construction"], ["docstatus", "=", 1]])
pi_details = []
pi_names = []

for pi in pis:
    doc = get_doc("Purchase Invoice", pi["name"])
    items = doc.get("items", [])
    taxes = doc.get("taxes", [])
    
    # Calculate base amount based on items
    base_total = sum(i.get("amount", 0) for i in items)
    
    tax_rows = []
    for t in taxes:
        tax_rows.append({
            "account_head": t.get("account_head"),
            "tax_amount": t.get("tax_amount")
        })

    pi_details.append({
        "name": doc.get("name"),
        "base_total": base_total,
        "grand_total": doc.get("grand_total"),
        "tax_withholding_net_total": doc.get("tax_withholding_net_total"),
        "tax_withholding_category": doc.get("tax_withholding_category"),
        "taxes": tax_rows,
        "items": [{"item_code": i.get("item_code"), "expense_account": i.get("expense_account"), "amount": i.get("amount")} for i in items]
    })
    pi_names.append(doc.get("name"))

# --- 4. GL Entries ---
gl_entries = []
if pi_names:
    gls = api_get("GL Entry",
                  [["voucher_type", "=", "Purchase Invoice"], ["voucher_no", "in", pi_names]],
                  fields=["name", "voucher_no", "account", "debit", "credit"],
                  limit=100)
    for g in gls:
        gl_entries.append({
            "voucher_no": g.get("voucher_no"),
            "account": g.get("account"),
            "debit": g.get("debit"),
            "credit": g.get("credit")
        })

result = {
    "task_start_time": task_start,
    "tax_categories": cat_details,
    "supplier_tax_category": supplier_tax_category,
    "purchase_invoices": pi_details,
    "gl_entries": gl_entries
}

with open("/tmp/contractor_tax_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="