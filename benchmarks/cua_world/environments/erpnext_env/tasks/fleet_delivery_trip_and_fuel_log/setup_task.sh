#!/bin/bash
# Setup script for fleet_delivery_trip_and_fuel_log task
# Creates driver, vehicle, stock, customers, and two submitted Delivery Notes.
# Agent must create Delivery Trip and Vehicle Log.

set -e
echo "=== Setting up fleet_delivery_trip_and_fuel_log ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "Waiting for ERPNext..."
wait_for_erpnext 300

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

python3 << 'PYEOF'
import requests, json, sys, time
from datetime import date

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

def get_doc(doctype, name):
    return session.get(f"{ERPNEXT_URL}/api/resource/{doctype}/{name}").json().get("data", {})

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
    doc = get_doc(doctype, name)
    doc["docstatus"] = 1
    r_sub = session.post(f"{ERPNEXT_URL}/api/method/frappe.client.submit", json={"doc": doc})
    return r_sub

# --- Wait for ERPNext master data (before_tests completion check) ---
print("Waiting for ERPNext master data (Company, Warehouses)...")
master_ready = False
for attempt in range(100):  # up to 25 minutes
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

# Re-login after waiting
session.post(f"{ERPNEXT_URL}/api/method/login",
             json={"usr": "Administrator", "pwd": "admin"})

# --- 1. Create Driver ---
print("Setting up Driver...")
driver_name = get_or_create("Driver", [["full_name", "=", "Alex Driver"]], {
    "full_name": "Alex Driver",
    "status": "Active"
})

# --- 2. Create Vehicle ---
print("Setting up Vehicle...")
vehicle_name = get_or_create("Vehicle", [["license_plate", "=", "WP-TRK-01"]], {
    "license_plate": "WP-TRK-01",
    "make": "Ford",
    "model": "F-150",
    "last_odometer": 15000,
    "status": "Active"
})

# --- 3. Create Customers ---
print("Setting up Customers...")
cust1 = get_or_create("Customer", [["customer_name", "=", "Chi-Chis"]], {
    "customer_name": "Chi-Chis", "customer_group": "All Customer Groups", "territory": "All Territories"
})
cust2 = get_or_create("Customer", [["customer_name", "=", "Consumers and Consumers Express"]], {
    "customer_name": "Consumers and Consumers Express", "customer_group": "All Customer Groups", "territory": "All Territories"
})

# --- 4. Ensure Item exists ---
print("Setting up Item...")
item_code = "Wind Turbine"
existing_item = api_get("Item", [["item_code", "=", item_code]])
if not existing_item:
    session.post(f"{ERPNEXT_URL}/api/resource/Item", json={
        "item_code": item_code, "item_name": item_code, "item_group": "All Item Groups",
        "stock_uom": "Nos", "is_stock_item": 1, "standard_rate": 21.00
    })

# --- Determine warehouses ---
wh_rows = api_get("Warehouse", fields=["name", "warehouse_name"])
stores_wh = next((w["name"] for w in wh_rows if "Stores" in w["name"]), "Stores - WP")

# --- 5. Add Inventory ---
print("Adding inventory via Stock Entry (Material Receipt)...")
se_resp = session.post(f"{ERPNEXT_URL}/api/resource/Stock Entry", json={
    "purpose": "Material Receipt",
    "company": "Wind Power LLC",
    "items": [{
        "item_code": item_code,
        "t_warehouse": stores_wh,
        "qty": 50,
        "basic_rate": 15.00
    }]
})
if se_resp.status_code in (200, 201):
    se_name = se_resp.json()["data"]["name"]
    safe_submit("Stock Entry", se_name)

# --- 6. Create Delivery Notes ---
print("Creating Delivery Notes...")
dn_names = []
for cust in [cust1, cust2]:
    dn_resp = session.post(f"{ERPNEXT_URL}/api/resource/Delivery Note", json={
        "customer": cust,
        "company": "Wind Power LLC",
        "items": [{
            "item_code": item_code,
            "qty": 2,
            "rate": 21.00,
            "warehouse": stores_wh
        }]
    })
    if dn_resp.status_code in (200, 201):
        dn_name = dn_resp.json()["data"]["name"]
        safe_submit("Delivery Note", dn_name)
        dn_names.append(dn_name)
        print(f"  Created and submitted Delivery Note: {dn_name} for {cust}")
    else:
        print(f"  Failed to create Delivery Note for {cust}: {dn_resp.text}", file=sys.stderr)

# Save baseline
baseline = {
    "driver": driver_name,
    "vehicle": vehicle_name,
    "delivery_notes": dn_names,
    "setup_time": time.time()
}
with open("/tmp/fleet_delivery_baseline.json", "w") as f:
    json.dump(baseline, f)

print("Baseline saved.")
PYEOF

# Ensure Firefox is pointing to Delivery Trips
echo "Launching Firefox..."
if pgrep -f firefox > /dev/null; then
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type --clearmodifiers "http://localhost:8080/app/delivery-trip"
    sleep 0.5
    DISPLAY=:1 xdotool key Return
else
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080/app/delivery-trip' &"
    sleep 5
fi

# Ensure maximized
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="