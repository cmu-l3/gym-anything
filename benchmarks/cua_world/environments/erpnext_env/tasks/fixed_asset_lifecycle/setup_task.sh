#!/bin/bash
# Setup script for fixed_asset_lifecycle task
# Creates Eagle Hardware supplier, CNC Milling Machine item, Locations, and Asset Category.
# Agent must create PI -> Edit/Submit auto-created Asset -> Create Asset Movement.

set -e
echo "=== Setting up fixed_asset_lifecycle ==="

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

# --- Wait for ERPNext master data (Company, Warehouses) ---
print("Waiting for ERPNext master data...")
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
    print("ERROR: ERPNext master data not available", file=sys.stderr)
    sys.exit(1)

session.post(f"{ERPNEXT_URL}/api/method/login", json={"usr": "Administrator", "pwd": "admin"})

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

# --- Locations ---
for loc in ["Main Factory", "Production Floor"]:
    get_or_create("Location", [["location_name", "=", loc]], {"location_name": loc})

# --- Supplier ---
get_or_create("Supplier", [["supplier_name", "=", "Eagle Hardware"]],
              {"supplier_name": "Eagle Hardware", "supplier_group": "All Supplier Groups"})

# --- Get default GL Accounts for Asset Category ---
fa_acc = api_get("Account", [["account_type", "=", "Fixed Asset"], ["is_group", "=", 0], ["company", "=", "Wind Power LLC"]])[0]["name"]
cwip_acc = api_get("Account", [["account_type", "=", "Capital Work in Progress"], ["is_group", "=", 0], ["company", "=", "Wind Power LLC"]])[0]["name"]
dep_exp_acc = api_get("Account", [["account_type", "=", "Depreciation"], ["is_group", "=", 0], ["company", "=", "Wind Power LLC"]])[0]["name"]
acc_dep_acc = api_get("Account", [["account_type", "=", "Accumulated Depreciation"], ["is_group", "=", 0], ["company", "=", "Wind Power LLC"]])[0]["name"]

# --- Asset Category ---
print("Setting up Asset Category: Manufacturing Equipment")
cat_exists = api_get("Asset Category", [["asset_category_name", "=", "Manufacturing Equipment"]])
if not cat_exists:
    r = session.post(f"{ERPNEXT_URL}/api/resource/Asset Category", json={
        "asset_category_name": "Manufacturing Equipment",
        "accounts": [{
            "company_name": "Wind Power LLC",
            "fixed_asset_account": fa_acc,
            "accumulated_depreciation_account": acc_dep_acc,
            "depreciation_expense_account": dep_exp_acc,
            "capital_work_in_progress_account": cwip_acc
        }],
        "finance_books": [{
            "depreciation_method": "Straight Line",
            "total_number_of_depreciations": 120,
            "frequency_of_depreciation": 1
        }]
    })
    if r.status_code in (200, 201):
        print("  Created Asset Category: Manufacturing Equipment")
    else:
        print(f"  ERROR creating Asset Category: {r.text[:200]}")

# --- Item ---
print("Setting up item: CNC Milling Machine")
item_exists = api_get("Item", [["item_code", "=", "CNC Milling Machine"]])
if not item_exists:
    r = session.post(f"{ERPNEXT_URL}/api/resource/Item", json={
        "item_code": "CNC Milling Machine",
        "item_name": "CNC Milling Machine",
        "item_group": "Products",
        "is_stock_item": 0,
        "is_fixed_asset": 1,
        "asset_category": "Manufacturing Equipment",
        "stock_uom": "Nos",
        "description": "High-precision CNC Milling Machine"
    })
    if r.status_code in (200, 201):
        print("  Created Item: CNC Milling Machine")

# --- Record Baselines (to prevent gaming) ---
existing_pis = [x["name"] for x in api_get("Purchase Invoice", [["supplier", "=", "Eagle Hardware"]])]
existing_assets = [x["name"] for x in api_get("Asset", [["item_code", "=", "CNC Milling Machine"]])]
existing_movements = [x["name"] for x in api_get("Asset Movement")]

baseline = {
    "purchase_invoices": existing_pis,
    "assets": existing_assets,
    "asset_movements": existing_movements,
    "task_start_time": time.time()
}

with open("/tmp/fixed_asset_lifecycle_baseline.json", "w") as f:
    json.dump(baseline, f)
print("Baseline saved.")
PYEOF

# Ensure Firefox is open to the Purchase Invoice list
echo "Opening Firefox to Purchase Invoice list..."
ensure_firefox_at "http://localhost:8080/app/purchase-invoice"

# Maximize and save initial state
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true
echo "=== Setup complete ==="