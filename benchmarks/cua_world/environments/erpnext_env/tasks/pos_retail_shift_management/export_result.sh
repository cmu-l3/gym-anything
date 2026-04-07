#!/bin/bash
# Export script for pos_retail_shift_management task
# Queries ERPNext for POS Opening Entries, POS Invoices, and POS Closing Entries.

echo "=== Exporting pos_retail_shift_management results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

take_screenshot /tmp/pos_retail_shift_management_final.png 2>/dev/null || true

python3 << 'PYEOF'
import requests, json, sys

ERPNEXT_URL = "http://localhost:8080"
session = requests.Session()

r = session.post(f"{ERPNEXT_URL}/api/method/login",
                 json={"usr": "Administrator", "pwd": "admin"})
if r.status_code != 200:
    print(f"ERROR: Login failed {r.status_code}", file=sys.stderr)
    sys.exit(1)

# Load baseline to exclude pre-existing documents
try:
    with open("/tmp/pos_retail_shift_management_baseline.json") as f:
        baseline = json.load(f)
except Exception:
    baseline = {"openings": [], "invoices": [], "closings": []}

def api_get(doctype, filters=None, fields=None, limit=50):
    params = {"limit_page_length": limit}
    if filters:
        params["filters"] = json.dumps(filters)
    if fields:
        params["fields"] = json.dumps(fields)
    return session.get(f"{ERPNEXT_URL}/api/resource/{doctype}", params=params).json().get("data", [])

def get_doc(doctype, name):
    return session.get(f"{ERPNEXT_URL}/api/resource/{doctype}/{name}").json().get("data", {})

# --- Fetch New POS Opening Entries ---
all_openings = api_get("POS Opening Entry", fields=["name", "pos_profile", "status", "docstatus"])
new_openings = [o for o in all_openings if o["name"] not in baseline.get("openings", [])]

# --- Fetch New POS Invoices ---
# POS Invoices usually stay docstatus=1 until consolidation, where they get status="Consolidated"
all_invoices = api_get("POS Invoice", [["docstatus", "=", 1]], fields=["name"])
new_invoices = [i for i in all_invoices if i["name"] not in baseline.get("invoices", [])]

invoice_details = []
for inv in new_invoices:
    doc = get_doc("POS Invoice", inv["name"])
    items = doc.get("items", [])
    payments = doc.get("payments", [])
    
    invoice_details.append({
        "name": doc.get("name"),
        "pos_profile": doc.get("pos_profile"),
        "customer": doc.get("customer"),
        "status": doc.get("status"),
        "grand_total": doc.get("grand_total", 0),
        "items": [
            {"item_code": itm.get("item_code"), "qty": itm.get("qty", 0), "amount": itm.get("amount", 0)}
            for itm in items
        ],
        "payments": [
            {"mode_of_payment": p.get("mode_of_payment"), "amount": p.get("amount", 0)}
            for p in payments
        ]
    })

# --- Fetch New POS Closing Entries ---
all_closings = api_get("POS Closing Entry", [["docstatus", "=", 1]], fields=["name"])
new_closings = [c for c in all_closings if c["name"] not in baseline.get("closings", [])]

closing_details = []
for cls in new_closings:
    doc = get_doc("POS Closing Entry", cls["name"])
    reconciliation = doc.get("payment_reconciliation", [])
    
    closing_details.append({
        "name": doc.get("name"),
        "pos_profile": doc.get("pos_profile"),
        "pos_opening_entry": doc.get("pos_opening_entry"),
        "status": doc.get("status"),
        "grand_total": doc.get("grand_total", 0),
        "payment_reconciliation": [
            {
                "mode_of_payment": row.get("mode_of_payment"),
                "expected_amount": row.get("expected_amount", 0),
                "closing_amount": row.get("closing_amount", 0)
            }
            for row in reconciliation
        ]
    })

result = {
    "pos_openings": new_openings,
    "pos_invoices": invoice_details,
    "pos_closings": closing_details
}

with open("/tmp/pos_retail_shift_management_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
print("\n=== Export complete: /tmp/pos_retail_shift_management_result.json ===")
PYEOF

echo "=== Export done ==="