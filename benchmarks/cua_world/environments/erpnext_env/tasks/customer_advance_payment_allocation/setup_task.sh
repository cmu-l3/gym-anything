#!/bin/bash
# Setup script for customer_advance_payment_allocation task
# Creates the customer 'Global Energy' and the service item 'Consulting Services'.
# Records baseline to ensure we only evaluate newly created documents.

set -e
echo "=== Setting up customer_advance_payment_allocation ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "Waiting for ERPNext..."
wait_for_erpnext 300

python3 << 'PYEOF'
import requests, json, sys, time

ERPNEXT_URL = "http://localhost:8080"
session = requests.Session()

r = session.post(f"{ERPNEXT_URL}/api/method/login",
                 json={"usr": "Administrator", "pwd": "admin"})
if r.status_code != 200:
    print(f"ERROR: Login failed {r.status_code}", file=sys.stderr)
    sys.exit(1)
print("Logged in successfully")

def api_get(doctype, filters=None, fields=None, limit=50):
    params = {"limit_page_length": limit}
    if filters:
        params["filters"] = json.dumps(filters)
    if fields:
        params["fields"] = json.dumps(fields)
    return session.get(f"{ERPNEXT_URL}/api/resource/{doctype}", params=params).json().get("data", [])

# --- Wait for ERPNext master data (before_tests completion check) ---
print("Waiting for ERPNext master data (Company)...")
master_ready = False
for attempt in range(100):  # up to 25 minutes
    try:
        companies = api_get("Company", [["company_name", "=", "Wind Power LLC"]])
        if companies:
            print(f"  Master data ready after {attempt * 15}s")
            master_ready = True
            break
    except Exception:
        pass
    print(f"  Master data not ready yet... ({attempt * 15}s elapsed)", flush=True)
    time.sleep(15)

if not master_ready:
    print("ERROR: ERPNext master data not available after 10 minutes", file=sys.stderr)
    sys.exit(1)

# Re-login after waiting
session.post(f"{ERPNEXT_URL}/api/method/login",
             json={"usr": "Administrator", "pwd": "admin"})

def get_or_create(doctype, filters, values):
    existing = api_get(doctype, filters)
    if existing:
        name = existing[0]["name"]
        print(f"  Found existing {doctype}: {name}")
        return name
    r = session.post(f"{ERPNEXT_URL}/api/resource/{doctype}", json=values)
    if r.status_code in (200, 201):
        name = r.json().get("data", {}).get("name", "unknown")
        print(f"  Created {doctype}: {name}")
        return name
    print(f"  ERROR creating {doctype}: {r.status_code} {r.text[:300]}", file=sys.stderr)
    return None

# --- Customer ---
print("Setting up customer: Global Energy")
get_or_create("Customer",
              [["customer_name", "=", "Global Energy"]],
              {"customer_name": "Global Energy",
               "customer_type": "Company",
               "customer_group": "All Customer Groups",
               "territory": "All Territories"})

# --- Item (Non-stock Service) ---
print("Setting up item: Consulting Services")
existing_item = api_get("Item", [["item_code", "=", "Consulting Services"]])
if not existing_item:
    r = session.post(f"{ERPNEXT_URL}/api/resource/Item", json={
        "item_code": "Consulting Services",
        "item_name": "Consulting Services",
        "item_group": "All Item Groups",
        "stock_uom": "Hour",
        "is_stock_item": 0,
        "include_item_in_manufacturing": 0,
        "description": "Professional Consulting Services"
    })
    if r.status_code in (200, 201):
        print(f"  Created Item: Consulting Services")
    else:
        print(f"  ERROR creating Item: {r.text[:200]}", file=sys.stderr)
else:
    print(f"  Found existing Item: Consulting Services")

# --- Record baseline state to prevent gaming ---
print("Recording baseline...")
existing_pes = [p["name"] for p in api_get("Payment Entry", [["party", "=", "Global Energy"]])]
existing_sis = [s["name"] for s in api_get("Sales Invoice", [["customer", "=", "Global Energy"]])]

baseline = {
    "existing_pes": existing_pes,
    "existing_sis": existing_sis,
    "timestamp": time.time()
}

with open("/tmp/customer_advance_payment_allocation_baseline.json", "w") as f:
    json.dump(baseline, f)

print(f"Baseline recorded: {len(existing_pes)} Payment Entries, {len(existing_sis)} Sales Invoices.")
PYEOF

# Navigate browser to Payment Entry list to help agent get started
ensure_firefox_at "http://localhost:8080/app/payment-entry" 2>/dev/null || true

# Take initial screenshot for reference
take_screenshot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Setup complete ==="