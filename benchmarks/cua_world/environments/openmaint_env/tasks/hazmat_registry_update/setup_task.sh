#!/bin/bash
set -e
echo "=== Setting up hazmat_registry_update ==="

source /workspace/scripts/task_utils.sh

if ! wait_for_openmaint 240; then
    echo "ERROR: OpenMaint is not reachable"
    exit 1
fi

# Create the report file on Desktop
cat > /home/ga/Desktop/asbestos_report_2026.txt << 'EOF'
ANNUAL ASBESTOS RE-INSPECTION REPORT
Building: Building A (BLD-A)
Date: 2026-05-12
Inspector: SafeEnvironment Inc.

SUMMARY OF FINDINGS:

1. EXISTING RECORDS REVIEW
   Item: HAZ-001 (Vinyl Floor Tiles)
   Location: Lobby (RM-A-001)
   Finding: ABATED. Material was removed during Jan 2026 renovation.
   Action Required: Update record to RETIRED/DISPOSED.

2. NEW INSPECTIONS & SAMPLING
   
   Sample ID: S-2026-A
   Location: Boiler Room (RM-A-002)
   Material: Thermal System Insulation (Pipe Lagging)
   Lab Result: POSITIVE (Chrysotile 15%)
   Action Required: CREATE NEW RECORD. 
                    Code: HAZ-002
                    Description: Asbestos Pipe Insulation
   
   Sample ID: S-2026-B
   Location: Roof Access (RM-A-RF)
   Material: Bituminous Roof Felt
   Lab Result: POSITIVE (Chrysotile 5%)
   Action Required: CREATE NEW RECORD.
                    Code: HAZ-003
                    Description: Asbestos Roof Felt

   Sample ID: S-2026-C
   Location: Office 102 (RM-A-102)
   Material: Drywall Joint Compound
   Lab Result: NEGATIVE (None Detected)
   Action Required: NONE. Do not log in register.

3. GENERAL REQUIREMENTS
   For all locations with CONFIRMED POSITIVE materials (Boiler Room and Roof Access),
   please update the Room record Notes to state:
   "WARNING: HAZMAT PRESENT - 2026 SURVEY"
EOF

chown ga:ga /home/ga/Desktop/asbestos_report_2026.txt

# Seed data in OpenMaint
python3 << 'PYEOF'
import sys, json, os, re
sys.path.insert(0, "/workspace/scripts")
from cmdbuild_api import *

token = get_token()
if not token:
    print("ERROR: Could not authenticate to CMDBuild API", file=sys.stderr)
    sys.exit(1)

print("Authenticated to CMDBuild API")

# 1. Identify Classes (Asset and Room)
asset_cls = None
room_cls = None

# Find Asset Class
for pattern in ["^Asset$", "^CI$", "^Equipment$", "TechnicalAsset"]:
    found = find_class(pattern, token)
    if found:
        asset_cls = found
        break
if not asset_cls:
    # Fallback to first reasonable CI class
    all_classes = list_classes(token)
    for c in all_classes:
        if "asset" in c.get("description", "").lower():
            asset_cls = c.get("_id")
            break

# Find Room Class
for pattern in ["^Room$", "^Space$", "^Location$"]:
    found = find_class(pattern, token)
    if found:
        room_cls = found
        break

print(f"Using Asset Class: {asset_cls}")
print(f"Using Room Class: {room_cls}")

if not asset_cls or not room_cls:
    print("ERROR: Could not identify required classes", file=sys.stderr)
    sys.exit(1)

# 2. Inspect Attributes to find correct field names
room_attrs = get_class_attributes(room_cls, token)
asset_attrs = get_class_attributes(asset_cls, token)

room_fields = {a.get("_id"): a.get("_id") for a in room_attrs}
asset_fields = {a.get("_id"): a.get("_id") for a in asset_attrs}

# Helper to find best field match
def find_field(fields, keywords):
    for f in fields:
        for k in keywords:
            if k.lower() in f.lower():
                return f
    return "Description" # Fallback

room_name_field = find_field(room_fields, ["Name", "Code", "Description"])
room_notes_field = find_field(room_fields, ["Notes", "Comment", "Description"])
asset_room_field = find_field(asset_fields, ["Room", "Location", "Space"])
asset_status_field = find_field(asset_fields, ["Status", "State"])

print(f"Fields Mapped: RoomName={room_name_field}, RoomNotes={room_notes_field}, AssetRoom={asset_room_field}, AssetStatus={asset_status_field}")

# 3. Create/Ensure Rooms Exist
rooms_to_create = [
    {"Code": "RM-A-001", "Description": "Lobby"},
    {"Code": "RM-A-002", "Description": "Boiler Room"},
    {"Code": "RM-A-RF", "Description": "Roof Access"},
    {"Code": "RM-A-102", "Description": "Office 102"}
]

room_ids = {}

for r in rooms_to_create:
    # Check if exists
    existing = get_cards(room_cls, token, limit=1, filter_str=f"filter={{\"attribute\":{{\"simple\":{{\"attribute\":\"Code\",\"operator\":\"equal\",\"value\":[\"{r['Code']}\"]}}}}}}")
    if existing:
        rid = existing[0]["_id"]
        # Reset notes if needed
        update_card(room_cls, rid, {room_notes_field: ""}, token)
        room_ids[r["Description"]] = rid
        print(f"Found existing room {r['Description']}: {rid}")
    else:
        rid = create_card(room_cls, r, token)
        room_ids[r["Description"]] = rid
        print(f"Created room {r['Description']}: {rid}")

# 4. Create Initial Asset (HAZ-001) in Lobby
haz1_data = {
    "Code": "HAZ-001",
    "Description": "Vinyl Floor Tiles - 9x9",
    asset_room_field: room_ids["Lobby"]
}
# Check if exists
existing_haz = get_cards(asset_cls, token, limit=1, filter_str=f"filter={{\"attribute\":{{\"simple\":{{\"attribute\":\"Code\",\"operator\":\"equal\",\"value\":[\"HAZ-001\"]}}}}}}")
haz1_id = None
if existing_haz:
    haz1_id = existing_haz[0]["_id"]
    # Ensure active
    # If status is a lookup, we might need to find the 'Active' lookup ID, but strictly setting _is_active usually helps
    # For simplicity in this generic env, we rely on the agent to change state
    print(f"Found existing HAZ-001: {haz1_id}")
else:
    haz1_id = create_card(asset_cls, haz1_data, token)
    print(f"Created HAZ-001: {haz1_id}")

# 5. Clean up any pre-existing HAZ-002 or HAZ-003 or contamination
for code in ["HAZ-002", "HAZ-003"]:
    existing = get_cards(asset_cls, token, limit=10, filter_str=f"filter={{\"attribute\":{{\"simple\":{{\"attribute\":\"Code\",\"operator\":\"equal\",\"value\":[\"{code}\"]}}}}}}")
    for e in existing:
        delete_card(asset_cls, e["_id"], token)
        print(f"Cleaned up stale {code}")

# Save baseline for verifier
baseline = {
    "asset_cls": asset_cls,
    "room_cls": room_cls,
    "room_ids": room_ids,
    "haz1_id": haz1_id,
    "room_notes_field": room_notes_field,
    "asset_room_field": asset_room_field,
    "asset_status_field": asset_status_field
}

save_baseline("/tmp/hazmat_baseline.json", baseline)
print("Baseline saved.")
PYEOF

# Start Firefox
pkill -f firefox || true
sleep 1
su - ga -c "DISPLAY=:1 firefox '$OPENMAINT_URL' > /tmp/firefox_task.log 2>&1 &"

if ! wait_for_window "firefox|mozilla|openmaint|cmdbuild" 40; then
    echo "WARNING: Firefox window not detected"
fi
focus_firefox || true

# Maximize
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Record start time
date +%s > /tmp/task_start_time.txt

echo "=== Setup complete ==="