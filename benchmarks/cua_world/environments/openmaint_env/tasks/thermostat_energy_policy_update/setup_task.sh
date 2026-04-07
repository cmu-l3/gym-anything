#!/bin/bash
set -e
echo "=== Setting up thermostat_energy_policy_update ==="

source /workspace/scripts/task_utils.sh

# Wait for OpenMaint to be ready
if ! wait_for_openmaint 240; then
    echo "ERROR: OpenMaint is not reachable"
    exit 1
fi

# Create Policy Memo
cat > /home/ga/Desktop/energy_policy_memo.txt << 'EOF'
ENERGY EFFICIENCY POLICY - MEMO 2026-A
Date: March 8, 2026
From: Director of Facilities
To: Maintenance Planning Team

Subject: Thermostat Configuration Update - HEADQUARTERS ONLY

We are rolling out the "Eco-2026" energy saving profile. Please update the CMMS records for the Headquarters building immediately.

INSTRUCTIONS:

1. Identify all Thermostats in the "Headquarters" building.

2. For "Smart" Thermostats (WiFi, Connected, App-controlled, Nest, Ecobee):
   - These devices support remote configuration.
   - Update the "Notes" field to append: "Profile: Eco-2026"

3. For "Legacy" Thermostats (Manual, Analog, or simple Digital non-WiFi):
   - These devices cannot support the new profile.
   - Update the "Notes" field to append: "Action: Replace"

RESTRICTIONS:
- Do NOT apply these changes to the Warehouse, Satellite Offices, or Retail branches at this time.
- Strict scope control is required for audit compliance.
EOF
chown ga:ga /home/ga/Desktop/energy_policy_memo.txt

# Seed Data via Python API
python3 << 'PYEOF'
import sys, json, os
sys.path.insert(0, "/workspace/scripts")
from cmdbuild_api import *

token = get_token()
if not token:
    print("ERROR: Could not authenticate to CMDBuild", file=sys.stderr)
    sys.exit(1)

print("Authenticated to CMDBuild API")

# 1. Find or Create Class (CI/Asset/Device)
target_cls = None
# Try to find a generic asset class
for pattern in ["Device", "Asset", "Equipment", "CI", "Inventory"]:
    found = find_class(pattern, token)
    if found:
        target_cls = found
        break

if not target_cls:
    # Fallback: list classes and pick one that looks right
    classes = list_classes(token)
    for c in classes:
        if "asset" in c.get("_id", "").lower():
            target_cls = c.get("_id")
            break

print(f"Using Asset Class: {target_cls}")

# 2. Get Attributes to find keys
attrs = get_class_attributes(target_cls, token)
attr_map = {a.get("_id", ""): a for a in attrs}

# Identify fields
desc_field = "Description"
notes_field = None
building_field = None
code_field = "Code"

for k, v in attr_map.items():
    k_lower = k.lower()
    if "notes" in k_lower or "remark" in k_lower or "comment" in k_lower:
        notes_field = k
    if "building" in k_lower or "location" in k_lower:
        building_field = k
    if "code" in k_lower:
        code_field = k

# Fallback for notes if not found
if not notes_field:
    notes_field = "Notes" 

print(f"Fields - Code: {code_field}, Desc: {desc_field}, Notes: {notes_field}, Building: {building_field}")

# 3. Create Buildings
hq_id = None
wh_id = None

# Check if they exist, else create
buildings = get_buildings(token)
for b in buildings:
    if "Headquarters" in b.get("Description", ""):
        hq_id = b.get("_id")
    if "Warehouse" in b.get("Description", ""):
        wh_id = b.get("_id")

if not hq_id:
    hq_id = create_card("Building", {"Code": "BLD-HQ", "Description": "Headquarters"}, token)
if not wh_id:
    wh_id = create_card("Building", {"Code": "BLD-WH", "Description": "Warehouse"}, token)

print(f"Buildings - HQ: {hq_id}, WH: {wh_id}")

# 4. Create Assets
# Definitions: (Smart=True/False, BuildingID, Description)
asset_defs = [
    # Headquarters - Smart
    {"code": "TH-HQ-001", "smart": True, "bld": hq_id, "desc": "Honeywell T9 Smart WiFi Thermostat"},
    {"code": "TH-HQ-002", "smart": True, "bld": hq_id, "desc": "Nest Learning Thermostat Gen3"},
    {"code": "TH-HQ-005", "smart": True, "bld": hq_id, "desc": "Ecobee SmartThermostat with Voice"},
    # Headquarters - Manual/Legacy
    {"code": "TH-HQ-003", "smart": False, "bld": hq_id, "desc": "Analog Round Manual Thermostat"},
    {"code": "TH-HQ-004", "smart": False, "bld": hq_id, "desc": "Digital Non-Programmable Thermostat"},
    # Warehouse - Contamination (Should NOT be touched)
    {"code": "TH-WH-001", "smart": True, "bld": wh_id, "desc": "Honeywell T9 Smart WiFi Thermostat"},
    {"code": "TH-WH-002", "smart": False, "bld": wh_id, "desc": "Analog Round Manual Thermostat"}
]

tracked_assets = {}

for adef in asset_defs:
    # Check if exists first to avoid dupes on re-runs
    existing = get_cards(target_cls, token, filter_str=f"filter={{\"attribute\":{{\"simple\":{{\"attribute\":\"{code_field}\",\"operator\":\"equal\",\"value\":\"{adef['code']}\"}}}}}}")
    
    card_data = {
        code_field: adef["code"],
        desc_field: adef["desc"],
        notes_field: "" # Ensure clean state
    }
    if building_field:
        card_data[building_field] = adef["bld"]

    if existing:
        card_id = existing[0]["_id"]
        update_card(target_cls, card_id, card_data, token)
        print(f"Updated existing asset {adef['code']}")
    else:
        card_id = create_card(target_cls, card_data, token)
        print(f"Created new asset {adef['code']}")
    
    tracked_assets[adef["code"]] = {
        "id": card_id,
        "is_smart": adef["smart"],
        "building_id": adef["bld"],
        "expected_action": "Eco-2026" if adef["bld"] == hq_id and adef["smart"] else ("Replace" if adef["bld"] == hq_id else "None")
    }

# 5. Save Baseline for Verification
baseline = {
    "asset_class": target_cls,
    "notes_field": notes_field,
    "hq_id": hq_id,
    "wh_id": wh_id,
    "assets": tracked_assets
}

with open("/tmp/thermostat_baseline.json", "w") as f:
    json.dump(baseline, f, indent=2)

print("Baseline saved.")
PYEOF

# Start Firefox
pkill -f firefox || true
sleep 1
su - ga -c "DISPLAY=:1 firefox '$OPENMAINT_URL' > /tmp/firefox_task.log 2>&1 &"

if ! wait_for_window "firefox|mozilla|openmaint" 40; then
    echo "WARNING: Firefox window not detected"
fi
focus_firefox || true

# Pre-type login if possible, but let agent do it primarily. 
# Just ensuring window is focused.

echo "=== Setup complete ==="