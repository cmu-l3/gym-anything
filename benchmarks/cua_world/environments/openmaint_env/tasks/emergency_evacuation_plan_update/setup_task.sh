#!/bin/bash
set -e
echo "=== Setting up emergency_evacuation_plan_update ==="

source /workspace/scripts/task_utils.sh

# Wait for OpenMaint to be ready
if ! wait_for_openmaint 240; then
    echo "ERROR: OpenMaint is not reachable"
    exit 1
fi

# Create Dummy PDF Files
DESKTOP_DIR="/home/ga/Desktop"
PLAN_DIR="$DESKTOP_DIR/Evacuation_Plans_2026"
mkdir -p "$PLAN_DIR"

# create dummy pdfs (just text files renamed, sufficient for upload test)
echo "dummy content for HQ" > "$PLAN_DIR/HQ_Evac_Route.pdf"
echo "dummy content for Warehouse" > "$PLAN_DIR/Warehouse_ZoneB_Draft.pdf"
echo "dummy content for North Annex" > "$PLAN_DIR/North_Annex_Evac.pdf"

# Create Instructions File
cat > "$DESKTOP_DIR/compliance_instructions.txt" << 'EOF'
=== 2026 FIRE SAFETY COMPLIANCE INSTRUCTIONS ===

1. HEADQUARTERS
   - File: HQ_Evac_Route.pdf
   - Action: Upload to building record.

2. LOGISTICS WAREHOUSE
   - File: Warehouse_ZoneB_Draft.pdf
   - Note: The filename says "Draft", but this version was approved yesterday by the Fire Marshal.
   - Action: Upload to building record.
   - REQUIREMENT: Set the Attachment Description to "Final Evacuation Plan 2026" so auditors know it is valid.

3. NORTH ANNEX
   - File: North_Annex_Evac.pdf
   - Note: This building was sold last month.
   - Action: Check the building status in OpenMaint. If Status is "Sold" or "Inactive", DO NOT upload the file. We do not maintain records for sold properties.

Login: admin / admin
EOF

chown -R ga:ga "$PLAN_DIR"
chown ga:ga "$DESKTOP_DIR/compliance_instructions.txt"

# Python script to seed the database with specific buildings
python3 << 'PYEOF'
import sys, json, os
sys.path.insert(0, "/workspace/scripts")
from cmdbuild_api import *

token = get_token()
if not token:
    print("ERROR: Could not authenticate to CMDBuild API", file=sys.stderr)
    sys.exit(1)

print("Authenticated to CMDBuild API")

# 1. Find Building Class
bld_cls = "Building" # Default
# Verify if it exists or find alias
if not find_class(bld_cls, token):
    found = find_class("Building", token)
    if found:
        bld_cls = found
    else:
        print("ERROR: Could not find Building class", file=sys.stderr)
        sys.exit(1)

print(f"Using Building class: {bld_cls}")

# 2. Define Target Buildings
targets = [
    {
        "Code": "BLD-HQ-001",
        "Description": "Headquarters",
        "Status": "Active" # Need to ensure valid lookup, or just rely on Description
    },
    {
        "Code": "BLD-WH-002",
        "Description": "Logistics Warehouse",
        "Status": "Active"
    },
    {
        "Code": "BLD-NA-099",
        "Description": "North Annex",
        "Status": "Sold" # Or Inactive
    }
]

# Helper to find lookup ID for status if needed
# For simplicity in this env, we might just set Description or Notes if Status is strict
# But let's try to update or create.

created_ids = {}

for t in targets:
    # Check if exists
    existing = get_cards(bld_cls, token, filter_str=f"filter={{\"attribute\":{{\"simple\":{{\"attribute\":\"Code\",\"operator\":\"equal\",\"value\":[\"{t['Code']}\"]}}}}}}")
    
    card_data = {
        "Code": t['Code'],
        "Description": t['Description']
    }
    
    # Try to set status if possible (it's often a lookup)
    # We will put the status text in Notes as a fallback visual cue if lookup fails
    card_data["Notes"] = f"Current Status: {t['Status']}"

    card_id = None
    if existing:
        card_id = existing[0]['_id']
        print(f"Updating existing building {t['Code']}")
        update_card(bld_cls, card_id, card_data, token)
    else:
        print(f"Creating new building {t['Code']}")
        card_id = create_card(bld_cls, card_data, token)
    
    created_ids[t['Description']] = card_id

    # Clean existing attachments
    if card_id:
        # CMDBuild V3 API for attachments: classes/{class}/cards/{id}/attachments
        atts = api("GET", f"classes/{bld_cls}/cards/{card_id}/attachments", token)
        if atts and "data" in atts:
            for att in atts["data"]:
                att_id = att.get("_id")
                print(f"Deleting old attachment {att_id} from {t['Code']}")
                api("DELETE", f"classes/{bld_cls}/cards/{card_id}/attachments/{att_id}", token)

# Save Baseline
baseline = {
    "building_class": bld_cls,
    "ids": created_ids
}
save_baseline("/tmp/evac_baseline.json", baseline)
print("Baseline saved.")

PYEOF

# Launch Firefox
pkill -f firefox || true
sleep 1
su - ga -c "DISPLAY=:1 firefox '$OPENMAINT_URL' > /tmp/firefox_task_evac.log 2>&1 &"

if ! wait_for_window "firefox|mozilla|openmaint|cmdbuild" 40; then
    echo "WARNING: Firefox window not detected"
fi

focus_firefox || true

# Maximize
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="