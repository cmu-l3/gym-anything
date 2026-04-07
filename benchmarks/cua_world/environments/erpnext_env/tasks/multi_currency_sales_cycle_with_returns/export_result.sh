#!/bin/bash
# Export script for multi_currency_sales_cycle_with_returns task
#
# Queries ERPNext API for all documents created by the agent:
#   - Sales Orders, Delivery Notes (incl. returns), Sales Invoices (incl. credit notes),
#     Payment Entries for Deutsche Windkraft GmbH
#   - Customer outstanding balance
#   - Wind Turbine stock in Stores warehouse

echo "=== Exporting multi_currency_sales_cycle_with_returns results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
take_screenshot /tmp/multi_currency_sales_cycle_with_returns_final.png \
    2>/dev/null || true

python3 << 'PYEOF'
import requests, json, sys

ERPNEXT_URL = "http://localhost:8080"
CUSTOMER = "Deutsche Windkraft GmbH"
session = requests.Session()

r = session.post(f"{ERPNEXT_URL}/api/method/login",
                 json={"usr": "Administrator", "pwd": "admin"})
if r.status_code != 200:
    print(f"ERROR: Login failed {r.status_code}", file=sys.stderr)
    sys.exit(1)

# Load baseline
try:
    with open("/tmp/multi_currency_sales_cycle_with_returns_baseline.json") as f:
        baseline = json.load(f)
    existing_sos = set(baseline.get("existing_sales_orders", []))
    existing_dns = set(baseline.get("existing_delivery_notes", []))
    existing_sis = set(baseline.get("existing_sales_invoices", []))
    existing_pes = set(baseline.get("existing_payment_entries", []))
except Exception:
    existing_sos = set()
    existing_dns = set()
    existing_sis = set()
    existing_pes = set()

def api_get(doctype, filters=None, fields=None, limit=50):
    params = {"limit_page_length": limit}
    if filters:
        params["filters"] = json.dumps(filters)
    if fields:
        params["fields"] = json.dumps(fields)
    return session.get(f"{ERPNEXT_URL}/api/resource/{doctype}",
                       params=params).json().get("data", [])

def get_doc(doctype, name):
    return session.get(
        f"{ERPNEXT_URL}/api/resource/{doctype}/{name}").json().get("data", {})

# --- Sales Orders ---
all_sos = api_get("Sales Order",
    [["customer", "=", CUSTOMER], ["docstatus", "=", 1]],
    fields=["name", "grand_total", "currency", "conversion_rate",
            "per_delivered", "per_billed", "status"])
new_sos = [so for so in all_sos if so["name"] not in existing_sos]

so_info = []
for so in new_sos:
    doc = get_doc("Sales Order", so["name"])
    items = doc.get("items", [])
    total_qty = sum(i.get("qty", 0) for i in items)
    so_info.append({
        "so_name": so["name"],
        "grand_total": so.get("grand_total", 0),
        "currency": so.get("currency", ""),
        "conversion_rate": so.get("conversion_rate", 0),
        "total_qty": total_qty,
        "per_delivered": so.get("per_delivered", 0),
        "per_billed": so.get("per_billed", 0),
        "status": so.get("status", "")
    })

# --- Delivery Notes (including returns) ---
all_dns = api_get("Delivery Note",
    [["customer", "=", CUSTOMER], ["docstatus", "=", 1]],
    fields=["name", "grand_total", "is_return", "return_against",
            "status", "currency"])
new_dns = [dn for dn in all_dns if dn["name"] not in existing_dns]

dn_info = []
for dn in new_dns:
    doc = get_doc("Delivery Note", dn["name"])
    items = doc.get("items", [])
    total_qty = sum(i.get("qty", 0) for i in items)
    wt_qty = sum(i.get("qty", 0) for i in items
                 if i.get("item_code") == "Wind Turbine")
    dn_info.append({
        "dn_name": dn["name"],
        "is_return": dn.get("is_return", 0),
        "return_against": dn.get("return_against", ""),
        "grand_total": dn.get("grand_total", 0),
        "currency": dn.get("currency", ""),
        "total_qty": total_qty,
        "wind_turbine_qty": wt_qty
    })

# --- Sales Invoices (including credit notes) ---
all_sis = api_get("Sales Invoice",
    [["customer", "=", CUSTOMER], ["docstatus", "=", 1]],
    fields=["name", "grand_total", "outstanding_amount", "is_return",
            "return_against", "currency", "conversion_rate", "status"])
new_sis = [si for si in all_sis if si["name"] not in existing_sis]

si_info = []
for si in new_sis:
    doc = get_doc("Sales Invoice", si["name"])
    items = doc.get("items", [])
    advances = doc.get("advances", [])
    total_qty = sum(i.get("qty", 0) for i in items)
    advance_allocated = sum(
        adv.get("allocated_amount", 0) for adv in advances
    )
    si_info.append({
        "si_name": si["name"],
        "grand_total": si.get("grand_total", 0),
        "outstanding_amount": si.get("outstanding_amount", 0),
        "is_return": si.get("is_return", 0),
        "return_against": si.get("return_against", ""),
        "currency": si.get("currency", ""),
        "conversion_rate": si.get("conversion_rate", 0),
        "total_qty": total_qty,
        "advance_allocated": advance_allocated
    })

# --- Payment Entries ---
all_pes = api_get("Payment Entry",
    [["party_type", "=", "Customer"], ["party", "=", CUSTOMER],
     ["docstatus", "=", 1]],
    fields=["name", "payment_type", "paid_amount", "received_amount",
            "source_exchange_rate", "target_exchange_rate",
            "unallocated_amount"])
new_pes = [pe for pe in all_pes if pe["name"] not in existing_pes]

pe_info = []
for pe in new_pes:
    doc = get_doc("Payment Entry", pe["name"])
    references = doc.get("references", [])
    refs = []
    for ref in references:
        refs.append({
            "reference_doctype": ref.get("reference_doctype", ""),
            "reference_name": ref.get("reference_name", ""),
            "allocated_amount": ref.get("allocated_amount", 0)
        })
    pe_info.append({
        "pe_name": pe["name"],
        "payment_type": pe.get("payment_type", ""),
        "paid_amount": pe.get("paid_amount", 0),
        "received_amount": pe.get("received_amount", 0),
        "source_exchange_rate": pe.get("source_exchange_rate", 0),
        "target_exchange_rate": pe.get("target_exchange_rate", 0),
        "unallocated_amount": pe.get("unallocated_amount", 0),
        "references": refs
    })

# --- Customer outstanding balance ---
# Sum outstanding from all submitted invoices (positive and negative/returns)
total_outstanding = sum(
    float(si.get("outstanding_amount", 0))
    for si in api_get("Sales Invoice",
        [["customer", "=", CUSTOMER], ["docstatus", "=", 1]],
        fields=["outstanding_amount"])
)

# --- Wind Turbine stock ---
try:
    stock_resp = session.get(
        f"{ERPNEXT_URL}/api/method/frappe.client.get_value",
        params={"doctype": "Bin",
                "filters": json.dumps([
                    ["item_code", "=", "Wind Turbine"],
                    ["warehouse", "like", "%Stores%"]
                ]),
                "fieldname": "actual_qty"})
    stock_val = stock_resp.json().get("message", {})
    wt_stock = float(stock_val.get("actual_qty", 0)) \
        if isinstance(stock_val, dict) else 0.0
except Exception:
    wt_stock = -1

# --- Construct result ---
result = {
    "customer": CUSTOMER,
    "sales_orders": so_info,
    "delivery_notes": dn_info,
    "sales_invoices": si_info,
    "payment_entries": pe_info,
    "customer_total_outstanding": total_outstanding,
    "wind_turbine_stock_stores": wt_stock
}

result_path = "/tmp/multi_currency_sales_cycle_with_returns_result.json"
with open(result_path, "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
print(f"\n=== Export complete: {result_path} ===")
PYEOF

chmod 666 /tmp/multi_currency_sales_cycle_with_returns_result.json \
    2>/dev/null || true

echo "=== Export done ==="
