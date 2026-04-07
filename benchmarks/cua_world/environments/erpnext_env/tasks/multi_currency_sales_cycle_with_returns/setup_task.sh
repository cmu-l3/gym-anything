#!/bin/bash
# Setup script for multi_currency_sales_cycle_with_returns task
#
# Creates:
#   - Customer "Deutsche Windkraft GmbH" with EUR as default currency
#   - Item "Wind Turbine" (stock item)
#   - Stock of 150 Wind Turbines in Stores warehouse
#   - Currency Exchange record: 1 EUR = 1.10 USD
#   - Company exchange gain/loss account configuration
#   - Baseline snapshot for anti-gaming verification
#
# Agent must then perform:
#   SO → advance PE → DN(60) → SINV(1200, allocate advance) → PE(400)
#   → return DN(-5) → credit note(-100) → DN(40) → SINV(800)
#   → PE(700 at rate 1.12) → verify balance = 0

set -e
echo "=== Setting up multi_currency_sales_cycle_with_returns ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "Waiting for ERPNext..."
wait_for_erpnext 300

python3 << 'PYEOF'
import requests, json, sys, time
from datetime import date, timedelta

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
    return session.get(f"{ERPNEXT_URL}/api/resource/{doctype}",
                       params=params).json().get("data", [])

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
    print(f"  ERROR creating {doctype}: {r.status_code} {r.text[:300]}",
          file=sys.stderr)
    return None

# --- Wait for ERPNext master data (Company + Warehouses) ---
print("Waiting for ERPNext master data (Company, Warehouses)...")
master_ready = False
for attempt in range(100):  # up to 25 minutes
    try:
        companies = api_get("Company",
                            [["company_name", "=", "Wind Power LLC"]])
        warehouses = api_get("Warehouse",
                             [["warehouse_name", "=", "Stores"]])
        if companies and warehouses:
            print(f"  Master data ready after {attempt * 15}s")
            master_ready = True
            break
    except Exception:
        pass
    print(f"  Master data not ready yet... ({attempt * 15}s elapsed)",
          flush=True)
    time.sleep(15)

if not master_ready:
    print("ERROR: ERPNext master data not available after 25 minutes",
          file=sys.stderr)
    sys.exit(1)

# Re-login after waiting
session.post(f"{ERPNEXT_URL}/api/method/login",
             json={"usr": "Administrator", "pwd": "admin"})

# --- Ensure EUR currency exists ---
print("Ensuring EUR currency exists...")
eur = api_get("Currency", [["name", "=", "EUR"]])
if not eur:
    r = session.post(f"{ERPNEXT_URL}/api/resource/Currency", json={
        "currency_name": "EUR",
        "symbol": "\u20ac",
        "fraction": "Cent",
        "fraction_units": 100,
        "enabled": 1
    })
    if r.status_code in (200, 201):
        print("  Created EUR currency")
    else:
        print(f"  EUR currency creation: {r.text[:200]}")
else:
    print("  EUR currency exists")

# --- Set Exchange Gain/Loss account on Company ---
print("Configuring Exchange Gain/Loss account...")
accs = api_get("Account", [
    ["account_name", "like", "%Exchange%"],
    ["company", "=", "Wind Power LLC"]
])
if accs:
    exchange_acc = accs[0]["name"]
    session.put(f"{ERPNEXT_URL}/api/resource/Company/Wind Power LLC", json={
        "exchange_gain_loss_account": exchange_acc,
        "unrealized_exchange_gain_loss_account": exchange_acc
    })
    print(f"  Set Exchange Gain/Loss account: {exchange_acc}")
else:
    print("  WARNING: No Exchange Gain/Loss account found")

# --- Create EUR Receivable Account ---
# Multi-currency Sales Invoices in EUR require a EUR-denominated receivable
# account. The default "Debtors - WP" is USD-only and rejects EUR invoices.
print("Creating EUR receivable account...")
eur_debtors = api_get("Account", [
    ["account_name", "=", "Debtors EUR"],
    ["company", "=", "Wind Power LLC"]
])
if not eur_debtors:
    # Find parent account (Accounts Receivable group)
    debtors_parent = api_get("Account", [
        ["account_name", "=", "Debtors"],
        ["company", "=", "Wind Power LLC"]
    ])
    parent = debtors_parent[0].get("parent_account",
        "Accounts Receivable - WP") if debtors_parent else "Accounts Receivable - WP"
    r = session.post(f"{ERPNEXT_URL}/api/resource/Account", json={
        "account_name": "Debtors EUR",
        "parent_account": parent,
        "company": "Wind Power LLC",
        "account_currency": "EUR",
        "account_type": "Receivable",
        "is_group": 0
    })
    if r.status_code in (200, 201):
        print(f"  Created account: Debtors EUR - WP (currency=EUR)")
    else:
        print(f"  WARNING: Could not create EUR Debtors: {r.text[:200]}")
else:
    print(f"  EUR Debtors account exists: {eur_debtors[0]['name']}")

# --- Customer: Deutsche Windkraft GmbH (EUR) ---
print("Setting up customer: Deutsche Windkraft GmbH")
cust_name = get_or_create("Customer",
              [["customer_name", "=", "Deutsche Windkraft GmbH"]],
              {"customer_name": "Deutsche Windkraft GmbH",
               "customer_type": "Company",
               "customer_group": "All Customer Groups",
               "territory": "All Territories",
               "default_currency": "EUR"})

# Set the EUR receivable account on the customer's party account
if cust_name:
    # Check if party account already set
    cust_doc = session.get(
        f"{ERPNEXT_URL}/api/resource/Customer/{cust_name}").json().get("data", {})
    party_accounts = cust_doc.get("accounts", [])
    has_wp_account = any(
        a.get("company") == "Wind Power LLC" for a in party_accounts
    )
    if not has_wp_account:
        party_accounts.append({
            "company": "Wind Power LLC",
            "account": "Debtors EUR - WP"
        })
        session.put(f"{ERPNEXT_URL}/api/resource/Customer/{cust_name}",
                    json={"accounts": party_accounts})
        print("  Set EUR receivable account on customer")
    else:
        print("  Customer party account already configured")

# --- Item: Wind Turbine ---
print("Setting up item: Wind Turbine")
existing_item = api_get("Item", [["item_code", "=", "Wind Turbine"]])
if not existing_item:
    r = session.post(f"{ERPNEXT_URL}/api/resource/Item", json={
        "item_code": "Wind Turbine",
        "item_name": "Wind Turbine",
        "item_group": "All Item Groups",
        "stock_uom": "Nos",
        "is_stock_item": 1,
        "description": "Small Wind Turbine for Home Use",
        "standard_rate": 21.00
    })
    if r.status_code in (200, 201):
        print("  Created Item: Wind Turbine")
    else:
        print(f"  ERROR creating Item: {r.text[:200]}", file=sys.stderr)
else:
    print("  Found existing Item: Wind Turbine")

# --- Determine warehouses ---
wh_rows = api_get("Warehouse", fields=["name", "warehouse_name"])
stores_wh = next((w["name"] for w in wh_rows
                   if "Stores" in w["name"]), "Stores - WP")
print(f"  Stores warehouse: {stores_wh}")

# --- Stock 150 Wind Turbines in Stores ---
def get_item_stock(item_code, warehouse):
    resp = session.get(
        f"{ERPNEXT_URL}/api/method/frappe.client.get_value",
        params={"doctype": "Bin",
                "filters": json.dumps([["item_code", "=", item_code],
                                        ["warehouse", "=", warehouse]]),
                "fieldname": "actual_qty"})
    val = resp.json().get("message", {})
    if isinstance(val, dict):
        return float(val.get("actual_qty", 0))
    return 0.0

needed_qty = 150
current_stock = get_item_stock("Wind Turbine", stores_wh)
print(f"  Current Wind Turbine stock in {stores_wh}: {current_stock}")

if current_stock < needed_qty:
    receipt_qty = int(needed_qty - current_stock)
    print(f"  Adding {receipt_qty} Wind Turbines to {stores_wh}...")
    se_data = {
        "stock_entry_type": "Material Receipt",
        "purpose": "Material Receipt",
        "company": "Wind Power LLC",
        "items": [{
            "item_code": "Wind Turbine",
            "qty": receipt_qty,
            "t_warehouse": stores_wh,
            "basic_rate": 15.00
        }]
    }
    r = session.post(f"{ERPNEXT_URL}/api/resource/Stock Entry", json=se_data)
    if r.status_code in (200, 201):
        se_name = r.json()["data"]["name"]
        print(f"  Created Stock Entry: {se_name}")
        # Submit using safe fetch-then-submit pattern
        time.sleep(1)
        r_fetch = session.get(
            f"{ERPNEXT_URL}/api/resource/Stock Entry/{se_name}")
        doc = r_fetch.json().get("data",
                                  {"doctype": "Stock Entry", "name": se_name})
        r_sub = session.post(
            f"{ERPNEXT_URL}/api/method/frappe.client.submit",
            json={"doc": doc})
        if r_sub.status_code in (200, 201):
            print(f"  Submitted Stock Entry: {se_name}")
        else:
            print(f"  WARNING: Could not submit SE: {r_sub.text[:200]}",
                  file=sys.stderr)
    else:
        print(f"  ERROR creating Stock Entry: {r.text[:200]}",
              file=sys.stderr)

# --- Currency Exchange: 1 EUR = 1.10 USD for today ---
today = str(date.today())
print(f"Setting up Currency Exchange rate for {today}...")
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
    else:
        print(f"  WARNING: CE creation: {r.text[:200]}")
else:
    print(f"  Currency Exchange already exists for {today}")

# --- Record baseline for anti-gaming ---
print("Recording baseline...")
existing_sos = [d["name"] for d in api_get("Sales Order",
    [["customer", "=", "Deutsche Windkraft GmbH"]])]
existing_dns = [d["name"] for d in api_get("Delivery Note",
    [["customer", "=", "Deutsche Windkraft GmbH"]])]
existing_sis = [d["name"] for d in api_get("Sales Invoice",
    [["customer", "=", "Deutsche Windkraft GmbH"]])]
existing_pes = [d["name"] for d in api_get("Payment Entry",
    [["party", "=", "Deutsche Windkraft GmbH"]])]

baseline = {
    "customer": "Deutsche Windkraft GmbH",
    "existing_sales_orders": existing_sos,
    "existing_delivery_notes": existing_dns,
    "existing_sales_invoices": existing_sis,
    "existing_payment_entries": existing_pes,
    "setup_date": today,
    "exchange_rate": 1.10
}

with open("/tmp/multi_currency_sales_cycle_with_returns_baseline.json",
          "w") as f:
    json.dump(baseline, f, indent=2)

print(f"Baseline recorded: {len(existing_sos)} SOs, {len(existing_dns)} DNs, "
      f"{len(existing_sis)} SIs, {len(existing_pes)} PEs")

print("\n=== Setup Summary ===")
print("Customer: Deutsche Windkraft GmbH (EUR)")
print("Item:     Wind Turbine (150 units stocked)")
print("Rate:     1 EUR = 1.10 USD")
print("Task:     SO -> advance -> DN(60) -> SINV(1200) -> PE(400)")
print("          -> return DN(-5) -> credit note(-100)")
print("          -> DN(40) -> SINV(800) -> PE(700 at 1.12)")
PYEOF

# Delete any stale result file before recording start time
rm -f /tmp/multi_currency_sales_cycle_with_returns_result.json 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt

# Navigate browser to Sales Order list
ensure_firefox_at "http://localhost:8080/app/sales-order" 2>/dev/null || true
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="
