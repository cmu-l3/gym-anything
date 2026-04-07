#!/bin/bash
set -e
echo "=== Setting up Emergency Flood Response Task ==="

source /workspace/scripts/task_utils.sh

# Wait for OpenMaint to be ready
if ! wait_for_openmaint 240; then
    echo "ERROR: OpenMaint is not reachable"
    exit 1
fi

# Create the Protocol File on Desktop
cat > /home/ga/Desktop/flood_protocol.txt << 'EOF'
EMERGENCY FLOOD PREPAREDNESS PROTOCOL
Date: 2026-03-08
Status: ACTIVATED

VULNERABLE ZONES (Basement Level):
- Room B-101 (Server/Archive Room)
- Room B-102 (Mechanical Room)
- Room B-103 (UPS/Power Room)

TRIAGE RULES:
1. ELECTRONICS / SENSITIVE DOCS: Tag description with " [RELOCATE]".
   (Servers, UPS units, Paper Archives, Hard Drives)

2. FIXED MECHANICAL / INFRASTRUCTURE: Tag description with " [PROTECT]".
   (Water Pumps, Boilers, HVAC handlers)

3. CRITICAL EXCEPTION:
   The SUMP PUMP is critical for flood mitigation. Even if portable,
   it must remain. Tag as " [PROTECT]".

4. NON-CRITICAL:
   Furniture (Desks, Chairs) and Janitorial Supplies.
   DO NOT TAG. Focus resources on critical items only.

INSTRUCTIONS:
Search the CMMS for assets in the vulnerable zones (search by Room number).
Update their Description field by appending the appropriate tag.
Then create a CRITICAL Work Order with description "Emergency Flood Prep - Asset Relocation" to mobilize the team.
EOF

chown ga:ga /home/ga/Desktop/flood_protocol.txt
chmod 644 /home/ga/Desktop/flood_protocol.txt

# Seed Data via Python Script
python3 << 'PYEOF'
import sys, json, os
sys.path.insert(0, "/workspace/scripts")
from cmdbuild_api import *

token = get_token()
if not token:
    print("ERROR: Could not authenticate to CMDBuild API", file=sys.stderr)
    sys.exit(1)

print("Authenticated to CMDBuild API")

# Find Asset Class
asset_cls = None
for pattern in [r"^CI$", r"^Asset$", r"InternalEquipment", r"Equipment", r"TechnicalAsset"]:
    found = find_class(pattern, token)
    if found:
        asset_cls = found
        break
if not asset_cls:
    # Fallback to creating a generic one if we could, but better to fail if env is broken
    print("ERROR: Could not find Asset class", file=sys.stderr)
    sys.exit(1)

print(f"Using Asset Class: {asset_cls}")

# Assets to Create
# We embed the Room in the description so search works easily
assets_to_seed = [
    {
        "Code": "AST-SRV-B01",
        "Description": "Room B-101: Dell PowerEdge Server Rack - Primary Database",
        "Type": "Electronics"
    },
    {
        "Code": "AST-ARCH-B01",
        "Description": "Room B-101: Physical Paper Archives - 2020-2025 Contracts",
        "Type": "Documents"
    },
    {
        "Code": "AST-PUMP-MAIN",
        "Description": "Room B-102: Main Water Circulator Pump P-101",
        "Type": "Mechanical"
    },
    {
        "Code": "AST-PUMP-SUMP",
        "Description": "Room B-102: Emergency Sump Pump SP-01",
        "Type": "Mechanical"
    },
    {
        "Code": "AST-UPS-B01",
        "Description": "Room B-103: APC Smart-UPS 5000VA - Backup Power",
        "Type": "Electronics"
    },
    {
        "Code": "AST-DESK-B01",
        "Description": "Room B-101: Office Desk - Standard L-Shape",
        "Type": "Furniture"
    }
]

seeded_ids = {}

# Create or Update Assets
for item in assets_to_seed:
    # Check if exists
    existing = get_cards(asset_cls, token, filter_str=f"filter={{\"attribute\":{{\"simple\":{{\"attribute\":\"Code\",\"operator\":\"equal\",\"value\":[\"{item['Code']}\"]}}}}}}")
    
    if existing:
        card_id = existing[0]['_id']
        # Reset description to clean state (remove any previous tags)
        update_card(asset_cls, card_id, {"Description": item['Description']}, token)
        seeded_ids[item['Code']] = card_id
        print(f"Reset existing asset {item['Code']}")
    else:
        card_id = create_card(asset_cls, item, token)
        seeded_ids[item['Code']] = card_id
        print(f"Created new asset {item['Code']}")

# Save Baseline
baseline = {
    "asset_class": asset_cls,
    "seeded_ids": seeded_ids,
    "initial_descriptions": {item['Code']: item['Description'] for item in assets_to_seed}
}
save_baseline("/tmp/flood_baseline.json", baseline)
print("Baseline saved to /tmp/flood_baseline.json")

# Record Work Order count for later check
wo_type, wo_cls = find_maintenance_class(token)
initial_wo_count = count_records(wo_type, wo_cls, token) if wo_cls else 0
with open("/tmp/initial_wo_count.txt", "w") as f:
    f.write(str(initial_wo_count))

PYEOF

# Record Start Time
date +%s > /tmp/task_start_time.txt

# Launch Firefox
pkill -f firefox || true
sleep 1
su - ga -c "DISPLAY=:1 firefox '$OPENMAINT_URL' > /tmp/firefox_task.log 2>&1 &"

# Setup Window
if wait_for_window "firefox|mozilla|openmaint" 60; then
    focus_firefox
    # Maximize
    WID=$(get_firefox_window_id)
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="