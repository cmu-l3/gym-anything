#!/bin/bash
set -e
echo "=== Setting up inventory_stock_policy_optimization ==="

source /workspace/scripts/task_utils.sh

# Ensure OpenMaint is reachable
if ! wait_for_openmaint 240; then
    echo "ERROR: OpenMaint is not reachable"
    exit 1
fi

# Generate the CSV policy file
cat > /home/ga/Desktop/inventory_policy.csv << 'CSV'
PartCode,Description,NewMin,NewMax,StatusRecommendation
SP-BELT-V46,V-Belt B46 Drive,5,20,Active
SP-FILT-2020,Pleated Filter 20x20x2,10,30,Active
SP-SENS-T10,Temp Sensor 10k Ohm,5,15,Active
SP-FUSE-OLD,Glass Fuse 15A (Legacy),0,0,Obsolete
SP-VALVE-05,Zone Valve Actuator 24V,2,5,Active
CSV
chown ga:ga /home/ga/Desktop/inventory_policy.csv

# Seed the database using Python API
python3 << 'PYEOF'
import sys, json, os
sys.path.insert(0, "/workspace/scripts")
from cmdbuild_api import *

token = get_token()
if not token:
    print("ERROR: Could not authenticate to CMDBuild API", file=sys.stderr)
    sys.exit(1)

print("Authenticated to CMDBuild API")

# 1. Find or Identify SparePart Class
# We look for "SparePart" or "Part" or "Material"
part_cls = find_class("SparePart", token)
if not part_cls:
    part_cls = find_class("Part", token)
if not part_cls:
    # If standard classes don't exist, we might need to use a generic CI class or similar
    # For this task's reliability, we'll try to find a suitable class or use "Product"
    part_cls = find_class("Product", token)

if not part_cls:
    print("ERROR: Could not find a Spare Part / Product class", file=sys.stderr)
    sys.exit(1)

print(f"Using Spare Part Class: {part_cls}")

# 2. Inspect attributes to map fields
attrs = get_class_attributes(part_cls, token)
attr_map = {a.get("_id"): a for a in attrs}

# Helper to find field names case-insensitive
def find_attr(keywords):
    for aid, a in attr_map.items():
        desc = a.get("description", "").lower()
        aid_lower = aid.lower()
        if any(k in aid_lower for k in keywords) or any(k in desc for k in keywords):
            return aid
    return None

min_field = find_attr(["min", "minimum"])
max_field = find_attr(["max", "maximum"])
qty_field = find_attr(["qty", "quantity", "stock", "onhand"])
code_field = "Code"
desc_field = "Description"

# Fallbacks if fields don't exist (in a real scenario we might create them, 
# but for this environment we assume standard schema or generic fields)
if not min_field: min_field = "MinimumStock" 
if not max_field: max_field = "MaximumStock"
if not qty_field: qty_field = "QtyOnHands" # or "Notes" if we must cheat

print(f"Mapped Fields: Min={min_field}, Max={max_field}, Qty={qty_field}")

# 3. Seed Data
# Format: Code, Description, CurrentQty, OldMin, OldMax
seed_data = [
    ("SP-BELT-V46", "V-Belt B46 Drive", 2, 1, 5),
    ("SP-FILT-2020", "Pleated Filter 20x20x2", 15, 5, 20),
    ("SP-SENS-T10", "Temp Sensor 10k Ohm", 4, 2, 10),
    ("SP-FUSE-OLD", "Glass Fuse 15A (Legacy)", 8, 5, 10),
    ("SP-VALVE-05", "Zone Valve Actuator 24V", 0, 0, 2)
]

seeded_ids = {}

for code, desc, qty, old_min, old_max in seed_data:
    # Check if exists
    existing = get_cards(part_cls, token, filter_str=f"filter={{\"attribute\":{{\"simple\":{{\"attribute\":\"{code_field}\",\"operator\":\"equal\",\"value\":[\"{code}\"]}}}}}}")
    
    card_data = {
        code_field: code,
        desc_field: desc,
        min_field: old_min,
        max_field: old_max,
        qty_field: qty,
        "_is_active": True # Ensure active start
    }
    
    # Clean up any existing cards with these codes to ensure fresh state
    if existing:
        for c in existing:
            # Update existing to reset state
            update_card(part_cls, c["_id"], card_data, token)
            seeded_ids[code] = c["_id"]
            print(f"Reset existing part {code}")
    else:
        # Create new
        cid = create_card(part_cls, card_data, token)
        seeded_ids[code] = cid
        print(f"Created new part {code}")

# 4. Save Baseline for Verification
baseline = {
    "part_class": part_cls,
    "min_field": min_field,
    "max_field": max_field,
    "qty_field": qty_field,
    "seeded_ids": seeded_ids
}
save_baseline("/tmp/inventory_baseline.json", baseline)

PYEOF

# Record start time
date +%s > /tmp/task_start_time.txt

# Launch Browser to Login Page
pkill -f firefox || true
sleep 1
su - ga -c "DISPLAY=:1 firefox '$OPENMAINT_URL' > /tmp/firefox.log 2>&1 &"

# Wait for window
wait_for_window "firefox|mozilla" 30
focus_firefox || true

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="