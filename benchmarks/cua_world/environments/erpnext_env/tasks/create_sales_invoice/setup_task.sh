#!/bin/bash
# Setup script for create_sales_invoice task
# Creates customer "Buttrey Food & Drug" and items from official ERPNext demo data.
# Data source: https://github.com/sahadnk72/erpnext-demo/tree/master/erpnext_demo/demo_docs

echo "=== Setting up create_sales_invoice ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "Waiting for ERPNext..."
wait_for_erpnext 60

# Login first
erpnext_login

python3 << 'PYEOF'
import requests
import json
import csv
import sys
from datetime import date, timedelta

ERPNEXT_URL = "http://localhost:8080"
session = requests.Session()

# Login
login_resp = session.post(f"{ERPNEXT_URL}/api/method/login", json={
    "usr": "Administrator",
    "pwd": "admin"
})
if login_resp.status_code != 200:
    print(f"ERROR: Login failed: {login_resp.status_code}", file=sys.stderr)
    sys.exit(1)
print("Logged in successfully")

def get_or_create(doctype, filters, values):
    """Get existing document or create a new one."""
    resp = session.get(f"{ERPNEXT_URL}/api/resource/{doctype}", params={
        "filters": json.dumps(filters),
        "limit_page_length": 1
    })
    data = resp.json().get("data", [])
    if data:
        print(f"  Found existing {doctype}: {data[0]['name']}")
        return data[0]["name"]

    resp = session.post(f"{ERPNEXT_URL}/api/resource/{doctype}", json=values)
    if resp.status_code in (200, 201):
        name = resp.json().get("data", {}).get("name", "unknown")
        print(f"  Created {doctype}: {name}")
        return name
    else:
        print(f"  ERROR creating {doctype}: {resp.status_code} {resp.text[:200]}", file=sys.stderr)
        return None

# --- Read customer from real demo data CSV ---
# Source: Customer.csv from official ERPNext demo (sahadnk72/erpnext-demo)
CUSTOMER_NAME = "Buttrey Food & Drug"
print(f"Setting up customer from demo data: {CUSTOMER_NAME}")

# Verify customer exists in our data file
try:
    with open("/workspace/data/customers.csv") as f:
        reader = csv.DictReader(f)
        cust_row = next((r for r in reader if r["customer_name"] == CUSTOMER_NAME), None)
    if cust_row:
        print(f"  Verified in data/customers.csv: {cust_row}")
except Exception as e:
    print(f"  Note: Could not read CSV ({e}), using hardcoded values from demo")
    cust_row = {"customer_name": CUSTOMER_NAME, "customer_type": "Company",
                "customer_group": "Commercial", "territory": "Rest Of The World"}

customer = get_or_create("Customer", [["customer_name", "=", CUSTOMER_NAME]], {
    "customer_name": CUSTOMER_NAME,
    "customer_type": "Company",
    "customer_group": "All Customer Groups",
    "territory": "All Territories"
})

# --- Read items from real demo data CSV ---
# Source: Item.csv + Item_Price.csv from official ERPNext demo
# Wind Turbine: selling rate $21, Small Wind Turbine for Home Use
# Wind Mill A Series: selling rate $28, Wind Mill A Series for Home Use 9ft
ITEMS_TO_CREATE = [
    {
        "item_code": "Wind Turbine",
        "item_name": "Wind Turbine",
        "item_group": "All Item Groups",
        "stock_uom": "Nos",
        "is_stock_item": 0,
        "standard_rate": 21.00,
        "description": "Small Wind Turbine for Home Use"
    },
    {
        "item_code": "Wind Mill A Series",
        "item_name": "Wind Mill A Series",
        "item_group": "All Item Groups",
        "stock_uom": "Nos",
        "is_stock_item": 0,
        "standard_rate": 28.00,
        "description": "Wind Mill A Series for Home Use 9ft"
    }
]

print("Setting up items from demo data...")
for item_def in ITEMS_TO_CREATE:
    get_or_create("Item", [["item_code", "=", item_def["item_code"]]], item_def)

# --- Save setup data ---
setup_data = {
    "customer_name": CUSTOMER_NAME,
    "data_source": "ERPNext official demo (sahadnk72/erpnext-demo)",
    "items": [
        {"item_code": "Wind Turbine", "item_name": "Wind Turbine", "qty": 15, "rate": 21.00},
        {"item_code": "Wind Mill A Series", "item_name": "Wind Mill A Series", "qty": 8, "rate": 28.00}
    ],
    "expected_total": 15 * 21.00 + 8 * 28.00,
    "posting_date": str(date.today()),
    "due_date": str(date.today() + timedelta(days=30))
}
with open("/tmp/create_sales_invoice_setup.json", "w") as f:
    json.dump(setup_data, f, indent=2)

print(f"\n=== Setup Summary ===")
print(f"Customer: {CUSTOMER_NAME}")
for item in setup_data["items"]:
    subtotal = item["qty"] * item["rate"]
    print(f"  Item: {item['item_name']} x{item['qty']} @ ${item['rate']:.2f} = ${subtotal:.2f}")
print(f"  Expected total: ${setup_data['expected_total']:.2f}")

PYEOF

if [ $? -ne 0 ]; then
    echo "ERROR: Python setup script failed!"
    exit 1
fi

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Navigate Firefox to ERPNext Sales Invoice list
ensure_firefox_at "$ERPNEXT_URL/app/sales-invoice/new"

sleep 3
take_screenshot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== Setup Complete ==="
echo "Setup data: /tmp/create_sales_invoice_setup.json"
