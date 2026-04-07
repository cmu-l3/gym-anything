#!/bin/bash
set -e
echo "=== Setting up multi_currency_purchase_payment ==="

# Source utilities if available
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

echo "Waiting for ERPNext to be ready..."
if type wait_for_erpnext > /dev/null 2>&1; then
    wait_for_erpnext 300
else
    sleep 30
fi

# Run Python script to setup required records in ERPNext
python3 << 'PYEOF'
import requests, json, sys, time
from datetime import date

ERPNEXT_URL = "http://localhost:8080"
session = requests.Session()

# Login as Administrator
r = session.post(f"{ERPNEXT_URL}/api/method/login",
                 json={"usr": "Administrator", "pwd": "admin"})
if r.status_code != 200:
    print(f"ERROR: Login failed {r.status_code}", file=sys.stderr)
    sys.exit(1)
print("Logged in successfully")

def api_get(doctype, filters=None, fields=None, limit=50):
    params = {"limit_page_length": limit}
    if filters: params["filters"] = json.dumps(filters)
    if fields: params["fields"] = json.dumps(fields)
    return session.get(f"{ERPNEXT_URL}/api/resource/{doctype}", params=params).json().get("data", [])

def get_or_create(doctype, filters, values):
    existing = api_get(doctype, filters)
    if existing:
        print(f"  Found existing {doctype}: {existing[0]['name']}")
        return existing[0]["name"]
    r = session.post(f"{ERPNEXT_URL}/api/resource/{doctype}", json=values)
    if r.status_code in (200, 201):
        name = r.json().get("data", {}).get("name")
        print(f"  Created {doctype}: {name}")
        return name
    print(f"  ERROR creating {doctype}: {r.text[:200]}", file=sys.stderr)
    return None

# Wait for ERPNext master data to be populated (Company)
print("Waiting for ERPNext master data (Company)...")
master_ready = False
for attempt in range(60):
    try:
        if api_get("Company", [["company_name", "=", "Wind Power LLC"]]):
            master_ready = True
            break
    except Exception: pass
    time.sleep(10)

if not master_ready:
    print("ERROR: ERPNext master data not available", file=sys.stderr)
    sys.exit(1)

# Re-login to ensure session is fresh
session.post(f"{ERPNEXT_URL}/api/method/login", json={"usr": "Administrator", "pwd": "admin"})

# Ensure Exchange Gain/Loss account is set on Company Defaults
accs = api_get("Account", [["account_name", "like", "%Exchange%"], ["company", "=", "Wind Power LLC"]])
if accs:
    exchange_acc = accs[0]["name"]
    session.put(f"{ERPNEXT_URL}/api/resource/Company/Wind Power LLC", json={
        "exchange_gain_loss_account": exchange_acc,
        "unrealized_exchange_gain_loss_account": exchange_acc
    })
    print(f"  Set Company Exchange Gain/Loss account to: {exchange_acc}")

# Create Supplier
get_or_create("Supplier", [["supplier_name", "=", "Schmidt Industrietechnik GmbH"]], {
    "supplier_name": "Schmidt Industrietechnik GmbH",
    "supplier_type": "Distributor",
    "supplier_group": "All Supplier Groups",
    "default_currency": "EUR"
})

# Create Item
get_or_create("Item", [["item_code", "=", "Precision Bearing"]], {
    "item_code": "Precision Bearing",
    "item_name": "Precision Bearing",
    "item_group": "All Item Groups",
    "stock_uom": "Nos",
    "is_stock_item": 1,
    "description": "High tolerance precision bearing"
})

# Create Currency Exchange rate for today (1 EUR = 1.10 USD)
today = str(date.today())
existing_ce = api_get("Currency Exchange", [
    ["from_currency", "=", "EUR"], 
    ["to_currency", "=", "USD"], 
    ["date", "=", today]
])
if not existing_ce:
    r = session.post(f"{ERPNEXT_URL}/api/resource/Currency Exchange", json={
        "date": today,
        "from_currency": "EUR",
        "to_currency": "USD",
        "exchange_rate": 1.10
    })
    if r.status_code in (200, 201):
        print(f"  Created Currency Exchange: 1 EUR = 1.10 USD for {today}")

# Save baseline Purchase Invoices to prevent gaming (must create a new one)
existing_pis = api_get("Purchase Invoice", [["supplier", "=", "Schmidt Industrietechnik GmbH"]])
baseline = {
    "existing_purchase_invoices": [pi["name"] for pi in existing_pis]
}
with open("/tmp/multi_currency_purchase_payment_baseline.json", "w") as f:
    json.dump(baseline, f)
print("Saved baseline state.")
PYEOF

echo "Navigating to Purchase Invoice list..."
if pgrep -f firefox > /dev/null; then
    # Help the agent by navigating to the right list via UI
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type --clearmodifiers "http://localhost:8080/app/purchase-invoice"
    sleep 0.5
    DISPLAY=:1 xdotool key Return
    sleep 3
fi

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="