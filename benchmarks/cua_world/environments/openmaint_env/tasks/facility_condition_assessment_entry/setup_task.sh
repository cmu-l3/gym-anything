#!/bin/bash
set -e
echo "=== Setting up facility_condition_assessment_entry ==="

source /workspace/scripts/task_utils.sh

# Wait for OpenMaint to be ready
if ! wait_for_openmaint 240; then
    echo "ERROR: OpenMaint is not reachable"
    exit 1
fi

# Create the CSV file on the desktop
cat > /home/ga/Desktop/fca_audit_2026.csv << 'CSV'
AssetCode,Description,ConditionScore,InspectorNotes,Classification
EQ-FCA-001,Main Air Handler,2,Severe corrosion on coils,Standard
EQ-FCA-002,Centrifugal Chiller,4,Operating within parameters,Standard
EQ-FCA-003,Hot Water Boiler,1,Cracked heat exchanger shell,Standard
EQ-FCA-004,Circulation Pump,5,Newly installed,Standard
EQ-FCA-005,Backup Generator,2,Engine block fatigue - historic unit,Heritage
CSV
chown ga:ga /home/ga/Desktop/fca_audit_2026.csv
chmod 644 /home/ga/Desktop/fca_audit_2026.csv

# Python script to seed the assets in OpenMaint
python3 << 'PYEOF'
import sys, json, os, time
sys.path.insert(0, "/workspace/scripts")
from cmdbuild_api import *

token = get_token()
if not token:
    print("ERROR: Could not authenticate to CMDBuild API", file=sys.stderr)
    sys.exit(1)

print("Authenticated to CMDBuild API")

# 1. Find a suitable Asset Class
# We prefer "MechanicalEquipment" or "Asset"
asset_cls = None
for name in ["MechanicalEquipment", "Equipment", "Asset", "CI"]:
    if find_class(name, token):
        asset_cls = name
        break

if not asset_cls:
    # Fallback search
    classes = list_classes(token)
    if classes:
        asset_cls = classes[0]["_id"]

if not asset_cls:
    print("ERROR: No suitable asset class found", file=sys.stderr)
    sys.exit(1)

print(f"Using Asset Class: {asset_cls}")

# 2. Create the 5 Assets
assets_data = [
    {"Code": "EQ-FCA-001", "Description": "Main Air Handler"},
    {"Code": "EQ-FCA-002", "Description": "Centrifugal Chiller"},
    {"Code": "EQ-FCA-003", "Description": "Hot Water Boiler"},
    {"Code": "EQ-FCA-004", "Description": "Circulation Pump"},
    {"Code": "EQ-FCA-005", "Description": "Backup Generator (Heritage)"}
]

created_ids = {}

for asset in assets_data:
    # Check if exists first to avoid duplicates on re-runs
    existing = get_cards(asset_cls, token, filter_str=f"filter={{\"attribute\":{{\"simple\":{{\"attribute\":\"Code\",\"operator\":\"equal\",\"value\":\"{asset['Code']}\"}}}}}}")
    
    if existing:
        print(f"Asset {asset['Code']} already exists, updating...")
        card_id = existing[0]["_id"]
        # Reset description/notes to clean state
        update_card(asset_cls, card_id, {"Notes": "", "Description": asset["Description"]}, token)
        created_ids[asset["Code"]] = card_id
    else:
        print(f"Creating {asset['Code']}...")
        card_id = create_card(asset_cls, asset, token)
        if card_id:
            created_ids[asset["Code"]] = card_id
        else:
            print(f"Failed to create {asset['Code']}")

# 3. Identify Work Order Class for verification later
wo_type, wo_cls = find_maintenance_class(token)
print(f"Work Order Class: {wo_cls} (type={wo_type})")

# 4. Save Baseline for Verification
baseline = {
    "asset_class": asset_cls,
    "wo_class": wo_cls,
    "wo_type": wo_type,
    "asset_ids": created_ids
}

with open("/tmp/fca_baseline.json", "w") as f:
    json.dump(baseline, f)

print("Setup complete.")
PYEOF

# Prepare browser state
pkill -f firefox || true
sleep 1
su - ga -c "DISPLAY=:1 firefox '$OPENMAINT_URL' > /tmp/firefox_task.log 2>&1 &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|openmaint"; then
        break
    fi
    sleep 1
done

# Maximize and focus
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
focus_firefox || true

# Screenshot initial state
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="