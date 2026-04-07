#!/bin/bash
set -e
echo "=== Setting up utility_meter_reading_log_and_anomaly_response ==="

source /workspace/scripts/task_utils.sh

# Ensure OpenMaint is running
if ! wait_for_openmaint 240; then
    echo "ERROR: OpenMaint is not reachable"
    exit 1
fi

# Create the CSV file on the desktop
cat > /home/ga/Desktop/meter_readings_mar2026.csv << 'CSV'
Code,Type,Previous,Current,Avg_Monthly,Status
UTIL-E-101,Electric,45000,45600,800,Active
UTIL-E-102,Electric,12000,14500,1000,Active
UTIL-W-201,Water,3200,3300,120,Active
UTIL-W-202,Water,8100,8600,200,Active
UTIL-G-005,Gas,5500,5500,100,Inactive
CSV
chown ga:ga /home/ga/Desktop/meter_readings_mar2026.csv

# Seed the database and record baseline
python3 << 'PYEOF'
import sys, json, os
sys.path.insert(0, "/workspace/scripts")
from cmdbuild_api import *

token = get_token()
if not token:
    print("ERROR: Could not authenticate to CMDBuild API", file=sys.stderr)
    sys.exit(1)

print("Authenticated to CMDBuild API")

# 1. Identify Asset Class
asset_cls = None
# Try to find a specific Meter class, fallback to generic Asset
for pattern in ["Meter", "UtilityMeter", "Asset", "CI", "Equipment"]:
    found = find_class(pattern, token)
    if found:
        asset_cls = found
        break

if not asset_cls:
    print("ERROR: Could not find suitable Asset class", file=sys.stderr)
    sys.exit(1)

print(f"Using Asset Class: {asset_cls}")

# 2. Identify/Create Building (for linkage)
buildings = get_buildings(token)
if not buildings:
    b_data = {"Code": "BLD-HQ", "Description": "Headquarters"}
    b_id = create_card("Building", b_data, token)
    buildings = [{"_id": b_id, "Code": "BLD-HQ"}]

bld_id = buildings[0].get("_id")

# 3. Seed Meters
meters_data = [
    {"Code": "UTIL-E-101", "Description": "Main Electric Feed - East Wing. History: 2026-02-15: 45000", "active": True},
    {"Code": "UTIL-E-102", "Description": "Server Room Sub-meter. History: 2026-02-15: 12000", "active": True},
    {"Code": "UTIL-W-201", "Description": "Domestic Water Main. History: 2026-02-15: 3200", "active": True},
    {"Code": "UTIL-W-202", "Description": "Irrigation System Feed. History: 2026-02-15: 8100", "active": True},
    {"Code": "UTIL-G-005", "Description": "Backup Generator Gas Line. History: 2026-02-15: 5500", "active": False}
]

meter_ids = {}

for m in meters_data:
    # Check if exists
    existing = get_cards(asset_cls, token, filter_str=f"filter={{\"attribute\":{{\"simple\":{{\"attribute\":\"Code\",\"operator\":\"equal\",\"value\":\"{m['Code']}\"}}}}}}")
    
    card_data = {
        "Code": m["Code"],
        "Description": m["Description"],
        "Building": bld_id  # Link to building
    }

    if existing:
        cid = existing[0]["_id"]
        update_card(asset_cls, cid, card_data, token)
        # Handle active status (CMDBuild usually uses _is_active or similar, or Status lookup)
        # We'll try to set the system status if possible, otherwise rely on the prompt telling the agent it's inactive in CSV
        # Note: 'Inactive' in CSV is the source of truth for the task logic, but we should try to match system state
        if not m["active"]:
             # Try to delete/archive if possible, or leave as is but note ID
             pass
    else:
        cid = create_card(asset_cls, card_data, token)
    
    meter_ids[m["Code"]] = cid
    print(f"Seeded {m['Code']} -> {cid}")

# 4. Identify Work Order Class
wo_type, wo_cls = find_maintenance_class(token)
print(f"Work Order Class: {wo_cls} (type={wo_type})")

# 5. Save Baseline
baseline = {
    "asset_class": asset_cls,
    "wo_class": wo_cls,
    "wo_type": wo_type,
    "meter_ids": meter_ids,
    "initial_wo_count": count_records(wo_type, wo_cls, token) if wo_cls else 0
}

save_baseline("/tmp/meter_baseline.json", baseline)
print("Baseline saved.")

PYEOF

# Start browser
pkill -f firefox || true
sleep 1
su - ga -c "DISPLAY=:1 firefox '$OPENMAINT_URL' > /tmp/firefox_task.log 2>&1 &"

if ! wait_for_window "firefox|mozilla|openmaint|cmdbuild" 40; then
    echo "WARNING: Firefox window not detected"
fi

focus_firefox || true

# Maximize
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="