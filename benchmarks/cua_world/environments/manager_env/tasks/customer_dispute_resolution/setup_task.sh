#!/bin/bash
# Setup script for customer_dispute_resolution task in Manager.io
# Creates sales invoices for Alfreds Futterkiste and Ernst Handel,
# and an unallocated receipt for Ernst Handel.
# Records baseline credit-note count for anti-gaming.

echo "=== Setting up customer_dispute_resolution task ==="

source /workspace/scripts/task_utils.sh

wait_for_manager 60

echo "$(date +%s)" > /tmp/manager_task_start_time

# ---------------------------------------------------------------------------
# Python: seed invoices + unallocated receipt
# ---------------------------------------------------------------------------
python3 - << 'PYEOF'
import requests
import re
import json
import sys
from datetime import date, timedelta

MANAGER_URL = "http://localhost:8080"

def login_and_get_bizkey():
    s = requests.Session()
    s.post(f"{MANAGER_URL}/login",
           data={"Username": "administrator"},
           allow_redirects=True)
    biz_page = s.get(f"{MANAGER_URL}/businesses").text
    m = re.search(r'start\?([^"&\s]+)[^<]{0,300}Northwind Traders', biz_page)
    if not m:
        m = re.search(r'start\?([^"&\s]+)', biz_page)
    if not m:
        print("ERROR: Could not get business key", file=sys.stderr)
        return None, None
    biz_key = m.group(1)
    s.get(f"{MANAGER_URL}/start?{biz_key}", allow_redirects=True)
    return s, biz_key

def get_field_name(s, biz_key, endpoint="customer-form"):
    form_page = s.get(f"{MANAGER_URL}/{endpoint}?{biz_key}").text
    m = re.search(r'name="([a-f0-9-]{36})" value="\{\}"', form_page)
    return m.group(1) if m else None

_UUID_RE = r'[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}'

def post_entity(s, biz_key, endpoint, field_name, data_dict):
    resp = s.post(
        f"{MANAGER_URL}/{endpoint}?{biz_key}",
        files={field_name: (None, json.dumps(data_dict))},
        allow_redirects=True
    )
    return resp.status_code

def get_entity_uuid(s, list_url, entity_name):
    """Find entity UUID by name from the list page HTML."""
    page = s.get(list_url).text.replace('&amp;', '&')
    idx = page.find(entity_name)
    if idx == -1:
        return None
    surrounding = page[max(0, idx - 1200):idx + 400]
    # Find any UUID in the surrounding text
    m = re.search(_UUID_RE, surrounding)
    return m.group(0) if m else None

s, biz_key = login_and_get_bizkey()
if not s:
    sys.exit(1)
print(f"Business key: {biz_key}")

field_name = get_field_name(s, biz_key)
if not field_name:
    print("ERROR: Could not get form field name", file=sys.stderr)
    sys.exit(1)
print(f"Form field: {field_name}")

# -----------------------------------------------------------------------
# Get existing customer and bank account UUIDs
# -----------------------------------------------------------------------
cust_list_url = f"{MANAGER_URL}/customers?{biz_key}"
alfreds_uuid = get_entity_uuid(s, cust_list_url, "Alfreds")
ernst_uuid = get_entity_uuid(s, cust_list_url, "Ernst Handel")
print(f"  Alfreds UUID: {alfreds_uuid}")
print(f"  Ernst Handel UUID: {ernst_uuid}")

bank_list_url = f"{MANAGER_URL}/bank-and-cash-accounts?{biz_key}"
cash_uuid = get_entity_uuid(s, bank_list_url, "Cash on Hand")
print(f"  Cash on Hand UUID: {cash_uuid}")

# -----------------------------------------------------------------------
# Create sales invoices
# -----------------------------------------------------------------------
today = date.today()

invoices = [
    {
        "ref": "INV-A002",
        "customer_uuid": alfreds_uuid,
        "customer_name": "Alfreds Futterkiste",
        "amount": 600.00,
        "description": "Assorted specialty beverages — wrong products shipped",
        "days_ago": 20
    },
    {
        "ref": "INV-A003",
        "customer_uuid": alfreds_uuid,
        "customer_name": "Alfreds Futterkiste",
        "amount": 180.00,
        "description": "Mixed food items order — pricing error on line 3",
        "days_ago": 15
    },
    {
        "ref": "INV-E001",
        "customer_uuid": ernst_uuid,
        "customer_name": "Ernst Handel",
        "amount": 1200.00,
        "description": "Standard beverage order — Chai Tea and Aniseed Syrup",
        "days_ago": 25
    },
    {
        "ref": "INV-E002",
        "customer_uuid": ernst_uuid,
        "customer_name": "Ernst Handel",
        "amount": 450.00,
        "description": "Supplemental beverage order",
        "days_ago": 18
    },
]

for inv in invoices:
    if not inv["customer_uuid"]:
        print(f"  SKIP {inv['ref']}: no customer UUID for {inv['customer_name']}")
        continue
    inv_date = (today - timedelta(days=inv["days_ago"])).isoformat()
    inv_data = {
        "Date": inv_date,
        "Reference": inv["ref"],
        "Customer": inv["customer_uuid"],
        "Lines": [
            {
                "Description": inv["description"],
                "Qty": 1.0,
                "UnitPrice": inv["amount"]
            }
        ]
    }
    code = post_entity(s, biz_key, "sales-invoice-form", field_name, inv_data)
    print(f"  Created {inv['ref']} ({inv['customer_name']}, ${inv['amount']}): HTTP {code}")

# -----------------------------------------------------------------------
# Create unallocated receipt for Ernst Handel ($450 to Cash on Hand)
# -----------------------------------------------------------------------
if ernst_uuid and cash_uuid:
    receipt_data = {
        "Date": (today - timedelta(days=10)).isoformat(),
        "BankAccount": cash_uuid,
        "Customer": ernst_uuid,
        "Amount": 450.00
    }
    code = post_entity(s, biz_key, "receipt-form", field_name, receipt_data)
    print(f"  Created unallocated receipt Ernst $450: HTTP {code}")
else:
    print("  SKIP receipt: missing Ernst or Cash on Hand UUID")

# -----------------------------------------------------------------------
# Record baseline credit-note count for anti-gaming
# -----------------------------------------------------------------------
cn_page = s.get(f"{MANAGER_URL}/credit-notes?{biz_key}").text.replace('&amp;', '&')
cn_count = len(set(re.findall(
    r'/credit-note-form\?[^&"\']+&([a-f0-9-]{36})', cn_page
)))
with open("/tmp/manager_task_credit_note_count", "w") as f:
    f.write(str(cn_count))
print(f"Baseline credit note count: {cn_count}")

# Record receipt baseline too (for anti-gaming on the allocation check)
rcpt_page = s.get(f"{MANAGER_URL}/receipts?{biz_key}").text.replace('&amp;', '&')
rcpt_count = len(set(re.findall(
    r'/receipt-form\?[^&"\']+&([a-f0-9-]{36})', rcpt_page
)))
with open("/tmp/manager_task_receipt_count", "w") as f:
    f.write(str(rcpt_count))
print(f"Baseline receipt count: {rcpt_count}")

print("Setup complete.")
PYEOF

take_screenshot /tmp/customer_dispute_resolution_start.png

echo "Opening Manager.io Sales Invoices module..."
open_manager_at "sales_invoices"

echo ""
echo "=== customer_dispute_resolution task setup complete ==="
echo ""
echo "TASK: Resolve customer invoice disputes for Northwind Traders"
echo ""
echo "Disputes to resolve:"
echo "  INV-A002  Alfreds Futterkiste  \$600.00  → full credit note (wrong products)"
echo "  INV-A003  Alfreds Futterkiste  \$180.00  → partial credit note \$60 (overcharge)"
echo "  INV-E002  Ernst Handel         \$450.00  → allocate existing unallocated receipt"
echo ""
echo "After resolving, view the Aged Receivables report."
echo "Login: administrator / (empty password)"
