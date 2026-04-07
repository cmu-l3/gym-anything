#!/bin/bash
# Export script for customer_advance_payment_allocation task
# Queries ERPNext for new Payment Entries and Sales Invoices for 'Global Energy'
# Validates amounts and linkage.

echo "=== Exporting customer_advance_payment_allocation results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
take_screenshot /tmp/customer_advance_payment_allocation_final.png 2>/dev/null || true

python3 << 'PYEOF'
import requests, json, sys

ERPNEXT_URL = "http://localhost:8080"
session = requests.Session()

r = session.post(f"{ERPNEXT_URL}/api/method/login",
                 json={"usr": "Administrator", "pwd": "admin"})
if r.status_code != 200:
    print(f"ERROR: Login failed {r.status_code}", file=sys.stderr)
    sys.exit(1)

# Load baseline to filter out pre-existing documents
try:
    with open("/tmp/customer_advance_payment_allocation_baseline.json") as f:
        baseline = json.load(f)
    existing_pes = set(baseline.get("existing_pes", []))
    existing_sis = set(baseline.get("existing_sis", []))
except Exception:
    existing_pes = set()
    existing_sis = set()

def api_get(doctype, filters=None, fields=None, limit=50):
    params = {"limit_page_length": limit}
    if filters:
        params["filters"] = json.dumps(filters)
    if fields:
        params["fields"] = json.dumps(fields)
    return session.get(f"{ERPNEXT_URL}/api/resource/{doctype}", params=params).json().get("data", [])

def get_doc(doctype, name):
    return session.get(f"{ERPNEXT_URL}/api/resource/{doctype}/{name}").json().get("data", {})

CUSTOMER = "Global Energy"

# --- Fetch New Sales Invoices ---
all_sis = api_get("Sales Invoice",
                   [["customer", "=", CUSTOMER], ["docstatus", "=", 1]],
                   fields=["name", "grand_total", "outstanding_amount", "status"])
new_sis = [si for si in all_sis if si["name"] not in existing_sis]

si_details = []
for si in new_sis:
    doc = get_doc("Sales Invoice", si["name"])
    items = doc.get("items", [])
    has_consulting = any(i.get("item_code") == "Consulting Services" for i in items)
    
    # Check advances child table in case allocation was done pre-submission
    advances = doc.get("advances", [])
    advance_linked_pes = [adv.get("reference_name") for adv in advances if adv.get("reference_doctype") == "Payment Entry"]
    
    si_details.append({
        "si_name": si["name"],
        "grand_total": si.get("grand_total", 0),
        "outstanding_amount": si.get("outstanding_amount", 0),
        "has_consulting_services": has_consulting,
        "advances_table": advance_linked_pes
    })

# --- Fetch New Payment Entries ---
all_pes = api_get("Payment Entry",
                   [["party_type", "=", "Customer"], ["party", "=", CUSTOMER], ["docstatus", "=", 1]],
                   fields=["name", "paid_amount", "unallocated_amount", "payment_type"])
new_pes = [pe for pe in all_pes if pe["name"] not in existing_pes]

pe_details = []
for pe in new_pes:
    doc = get_doc("Payment Entry", pe["name"])
    references = doc.get("references", [])
    refs = []
    for ref in references:
        if ref.get("reference_doctype") == "Sales Invoice":
            refs.append({
                "reference_name": ref.get("reference_name"),
                "allocated_amount": ref.get("allocated_amount", 0)
            })
            
    pe_details.append({
        "pe_name": pe["name"],
        "payment_type": pe.get("payment_type"),
        "paid_amount": pe.get("paid_amount", 0),
        "unallocated_amount": pe.get("unallocated_amount", 0),
        "references": refs
    })

result = {
    "customer": CUSTOMER,
    "payment_entries": pe_details,
    "sales_invoices": si_details
}

with open("/tmp/customer_advance_payment_allocation_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
print("\n=== Export complete: /tmp/customer_advance_payment_allocation_result.json ===")
PYEOF

echo "=== Export done ==="