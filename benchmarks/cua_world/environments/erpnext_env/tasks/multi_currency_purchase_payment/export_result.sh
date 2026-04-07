#!/bin/bash
set -e
echo "=== Exporting multi_currency_purchase_payment results ==="

# Take final screenshot for visual verification
DISPLAY=:1 scrot /tmp/multi_currency_purchase_payment_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/multi_currency_purchase_payment_final.png 2>/dev/null || true

# Run Python script to query the database/API for results
python3 << 'PYEOF'
import requests, json, sys

ERPNEXT_URL = "http://localhost:8080"
session = requests.Session()

# Login
r = session.post(f"{ERPNEXT_URL}/api/method/login",
                 json={"usr": "Administrator", "pwd": "admin"})
if r.status_code != 200:
    print(f"ERROR: Login failed {r.status_code}", file=sys.stderr)
    sys.exit(1)

# Load baseline state
try:
    with open("/tmp/multi_currency_purchase_payment_baseline.json") as f:
        baseline = json.load(f)
    existing_pis = set(baseline.get("existing_purchase_invoices", []))
except Exception:
    existing_pis = set()

def api_get(doctype, filters=None, fields=None):
    params = {"limit_page_length": 50}
    if filters: params["filters"] = json.dumps(filters)
    if fields: params["fields"] = json.dumps(fields)
    return session.get(f"{ERPNEXT_URL}/api/resource/{doctype}", params=params).json().get("data", [])

# Fetch newly created Purchase Invoices for the supplier
pi_list = api_get("Purchase Invoice",
                  [["supplier", "=", "Schmidt Industrietechnik GmbH"]],
                  fields=["name", "currency", "conversion_rate", "grand_total", "base_grand_total", "outstanding_amount", "docstatus"])

new_pis = [pi for pi in pi_list if pi["name"] not in existing_pis]

# Fetch Payment Entries for the supplier
pe_list = api_get("Payment Entry",
                  [["party_type", "=", "Supplier"], ["party", "=", "Schmidt Industrietechnik GmbH"], ["docstatus", "=", 1]],
                  fields=["name", "payment_type", "paid_amount", "received_amount", "source_exchange_rate", "target_exchange_rate"])

# Construct results payload
result = {
    "purchase_invoices": new_pis,
    "payment_entries": pe_list
}

# Write results to the designated tmp file
result_path = "/tmp/multi_currency_purchase_payment_result.json"
with open(result_path, "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
print(f"Result exported to {result_path}")
PYEOF

# Ensure file permissions
chmod 666 /tmp/multi_currency_purchase_payment_result.json 2>/dev/null || true

echo "=== Export done ==="