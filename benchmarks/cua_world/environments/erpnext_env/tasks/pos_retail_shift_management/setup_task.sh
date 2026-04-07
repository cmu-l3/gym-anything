#!/bin/bash
# Setup script for pos_retail_shift_management task
# Creates POS Profile, items, pre-stocks them, and records the baseline.

set -e
echo "=== Setting up pos_retail_shift_management ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "Waiting for ERPNext..."
wait_for_erpnext 300

python3 << 'PYEOF'
import requests, json, sys, time

ERPNEXT_URL = "http://localhost:8080"
session = requests.Session()

# --- Login ---
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

def safe_submit(doctype, name):
    time.sleep(1)
    r_fetch = session.get(f"{ERPNEXT_URL}/api/resource/{doctype}/{name}")
    doc = r_fetch.json().get("data", {"doctype": doctype, "name": name})
    if doc.get("docstatus") == 1:
        return True
    r_sub = session.post(f"{ERPNEXT_URL}/api/method/frappe.client.submit", json={"doc": doc})
    return r_sub.status_code == 200

# --- Wait for ERPNext master data ---
print("Waiting for ERPNext master data (Company, Warehouses)...")
master_ready = False
for attempt in range(100):
    try:
        companies = api_get("Company", [["company_name", "=", "Wind Power LLC"]])
        warehouses = api_get("Warehouse", [["warehouse_name", "=", "Stores"]])
        if companies and warehouses:
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

# Re-login
session.post(f"{ERPNEXT_URL}/api/method/login", json={"usr": "Administrator", "pwd": "admin"})

# --- Setup Warehouse ---
wh_rows = api_get("Warehouse", fields=["name", "warehouse_name"])
stores_wh = next((w["name"] for w in wh_rows if "Stores" in w["name"]), "Stores - WP")
print(f"Using warehouse: {stores_wh}")

# --- Setup Customer ---
print("Setting up customer...")
get_or_create("Customer",
              [["customer_name", "=", "Walk In"]],
              {"customer_name": "Walk In",
               "customer_type": "Company",
               "customer_group": "All Customer Groups",
               "territory": "All Territories"})

# --- Setup Items and Pricing ---
items_to_ensure = [
    {"item_code": "Solar Lantern", "item_name": "Solar Lantern", "rate": 25.0, "is_stock_item": 1, "stock_uom": "Nos", "item_group": "All Item Groups"},
    {"item_code": "Battery Pack", "item_name": "Battery Pack", "rate": 120.0, "is_stock_item": 1, "stock_uom": "Nos", "item_group": "All Item Groups"}
]

for item in items_to_ensure:
    print(f"Setting up item: {item['item_code']}")
    existing = api_get("Item", [["item_code", "=", item["item_code"]]])
    if not existing:
        r = session.post(f"{ERPNEXT_URL}/api/resource/Item", json={
            "item_code": item["item_code"],
            "item_name": item["item_name"],
            "item_group": item["item_group"],
            "stock_uom": item["stock_uom"],
            "is_stock_item": item["is_stock_item"],
            "standard_rate": item["rate"]
        })
    
    # Ensure standard selling price
    existing_price = api_get("Item Price", [["item_code", "=", item["item_code"]], ["price_list", "=", "Standard Selling"]])
    if not existing_price:
        session.post(f"{ERPNEXT_URL}/api/resource/Item Price", json={
            "item_code": item["item_code"],
            "price_list": "Standard Selling",
            "price_list_rate": item["rate"]
        })

# --- Stock Items (Material Receipt) ---
print("Stocking items...")
se = {
    "purpose": "Material Receipt",
    "company": "Wind Power LLC",
    "items": [
        {"item_code": "Solar Lantern", "t_warehouse": stores_wh, "qty": 100, "basic_rate": 10},
        {"item_code": "Battery Pack", "t_warehouse": stores_wh, "qty": 100, "basic_rate": 50}
    ]
}
se_name = get_or_create("Stock Entry", [["purpose", "=", "Material Receipt"], ["docstatus", "=", 0]], se)
safe_submit("Stock Entry", se_name)

# --- Setup Accounts & Mode of Payment ---
print("Setting up Accounts and Modes of Payment...")
cash_accs = api_get("Account", [["account_name", "like", "Cash%"], ["is_group", "=", 0], ["company", "=", "Wind Power LLC"]])
bank_accs = api_get("Account", [["account_name", "like", "Bank%"], ["is_group", "=", 0], ["company", "=", "Wind Power LLC"]])
income_accs = api_get("Account", [["account_name", "like", "Sales%"], ["is_group", "=", 0], ["company", "=", "Wind Power LLC"]])
expense_accs = api_get("Account", [["account_name", "like", "Cost of Goods Sold%"], ["is_group", "=", 0], ["company", "=", "Wind Power LLC"]])

cash_acc = cash_accs[0]["name"] if cash_accs else ""
bank_acc = bank_accs[0]["name"] if bank_accs else ""
income_acc = income_accs[0]["name"] if income_accs else ""
expense_acc = expense_accs[0]["name"] if expense_accs else ""

for mop, acc, typ in [("Cash", cash_acc, "Cash"), ("Card", bank_acc, "Bank")]:
    existing_mop = api_get("Mode of Payment", [["mode_of_payment", "=", mop]])
    if not existing_mop:
        session.post(f"{ERPNEXT_URL}/api/resource/Mode of Payment", json={
            "mode_of_payment": mop, "enabled": 1, "type": typ,
            "accounts": [{"company": "Wind Power LLC", "default_account": acc}]
        })
    else:
        doc = session.get(f"{ERPNEXT_URL}/api/resource/Mode of Payment/{mop}").json()["data"]
        accounts = doc.get("accounts", [])
        if not any(a.get("company") == "Wind Power LLC" for a in accounts):
            doc["accounts"].append({"company": "Wind Power LLC", "default_account": acc})
            session.put(f"{ERPNEXT_URL}/api/resource/Mode of Payment/{mop}", json=doc)

# --- Setup POS Profile ---
print("Setting up POS Profile...")
profile_name = "Retail Storefront"
existing_profile = api_get("POS Profile", [["name", "=", profile_name]])
if not existing_profile:
    profile_data = {
        "name": profile_name,
        "company": "Wind Power LLC",
        "warehouse": stores_wh,
        "customer": "Walk In",
        "income_account": income_acc,
        "expense_account": expense_acc,
        "currency": "USD",
        "append_free_issue_items": 0,
        "payments": [
            {"mode_of_payment": "Cash", "default": 1},
            {"mode_of_payment": "Card", "default": 0}
        ]
    }
    r = session.post(f"{ERPNEXT_URL}/api/resource/POS Profile", json=profile_data)
    if r.status_code not in (200, 201):
        print(f"  ERROR creating POS Profile: {r.text}", file=sys.stderr)
else:
    print(f"  Found existing POS Profile")

# --- Record Baseline ---
openings = api_get("POS Opening Entry", fields=["name"])
invoices = api_get("POS Invoice", fields=["name"])
closings = api_get("POS Closing Entry", fields=["name"])

baseline = {
    "openings": [o["name"] for o in openings],
    "invoices": [i["name"] for i in invoices],
    "closings": [c["name"] for c in closings]
}
with open("/tmp/pos_retail_shift_management_baseline.json", "w") as f:
    json.dump(baseline, f)

print("Baseline recorded.")
PYEOF

echo "=== Task setup complete ==="