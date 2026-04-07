#!/bin/bash
# Export script for fleet_delivery_trip_and_fuel_log task
# Queries ERPNext for Delivery Trips and Vehicle Logs created after setup.

echo "=== Exporting fleet_delivery_trip_and_fuel_log results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

take_screenshot /tmp/fleet_delivery_final.png 2>/dev/null || true

python3 << 'PYEOF'
import requests, json, sys, os

ERPNEXT_URL = "http://localhost:8080"
session = requests.Session()

# Login
r = session.post(f"{ERPNEXT_URL}/api/method/login",
                 json={"usr": "Administrator", "pwd": "admin"})
if r.status_code != 200:
    print(f"ERROR: Login failed {r.status_code}", file=sys.stderr)
    sys.exit(1)

# Load Baseline
try:
    with open("/tmp/fleet_delivery_baseline.json") as f:
        baseline = json.load(f)
except Exception:
    baseline = {}

target_dns = baseline.get("delivery_notes", [])
driver_name = baseline.get("driver", "Alex Driver")
vehicle_name = baseline.get("vehicle", "WP-TRK-01")

def api_get(doctype, filters=None, fields=None, limit=20):
    params = {"limit_page_length": limit}
    if filters:
        params["filters"] = json.dumps(filters)
    if fields:
        params["fields"] = json.dumps(fields)
    return session.get(f"{ERPNEXT_URL}/api/resource/{doctype}", params=params).json().get("data", [])

def get_doc(doctype, name):
    return session.get(f"{ERPNEXT_URL}/api/resource/{doctype}/{name}").json().get("data", {})

# --- Find Delivery Trips ---
dt_list = api_get("Delivery Trip", 
                  [["docstatus", "=", 1]], 
                  fields=["name", "driver", "vehicle", "status"])

dt_info = []
for dt in dt_list:
    doc = get_doc("Delivery Trip", dt["name"])
    stops = []
    for s in doc.get("delivery_stops", []):
        if s.get("delivery_document"):
            stops.append(s.get("delivery_document"))
    
    dt_info.append({
        "trip_name": dt["name"],
        "driver": doc.get("driver"),
        "vehicle": doc.get("vehicle"),
        "status": dt.get("status"),
        "stops": stops
    })

# --- Find Vehicle Logs ---
vl_list = api_get("Vehicle Log", 
                  [["license_plate", "=", vehicle_name], ["docstatus", "=", 1]], 
                  fields=["name", "odometer", "price", "fuel_qty", "supplier"])

vl_info = []
for vl in vl_list:
    doc = get_doc("Vehicle Log", vl["name"])
    
    # Calculate fuel cost. Usually fuel_qty * price, or some users might just put amount in price/amount field.
    fuel_qty = float(doc.get("fuel_qty", 0))
    price = float(doc.get("price", 0))
    fuel_cost = fuel_qty * price
    if fuel_cost == 0:
        fuel_cost = price # fallback in case they put total in price
        
    alt_amount = float(doc.get("amount", doc.get("total_amount", 0)))
    
    # Check expenses child table if used
    total_expenses = sum(float(e.get("expense_amount", 0)) for e in doc.get("service_detail", []))
    
    vl_info.append({
        "log_name": vl["name"],
        "odometer": int(doc.get("odometer", 0)),
        "fuel_qty": fuel_qty,
        "price": price,
        "computed_fuel_cost": fuel_cost,
        "alt_amount": alt_amount,
        "total_expenses": total_expenses
    })

result = {
    "target_driver": driver_name,
    "target_vehicle": vehicle_name,
    "target_delivery_notes": target_dns,
    "delivery_trips": dt_info,
    "vehicle_logs": vl_info
}

with open("/tmp/fleet_delivery_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="