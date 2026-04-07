#!/bin/bash
set -e
echo "=== Setting up Room Occupancy Audit Update ==="

source /workspace/scripts/task_utils.sh

# Wait for OpenMaint to be ready
if ! wait_for_openmaint 240; then
    echo "ERROR: OpenMaint is not reachable"
    exit 1
fi

# Create the rules file on desktop
cat > /home/ga/Desktop/occupancy_rules.txt << 'EOF'
SPACE UTILIZATION AUDIT RULES
=============================

Please update the 'Notes' field for the target rooms based on the 
'Description' field content.

LOGIC RULES:

1. OFFICE OCCUPIED:
   IF Type is 'Office' AND User is NOT 'None'
   -> Set Notes to: Occupied

2. OFFICE VACANT:
   IF Type is 'Office' AND User is 'None'
   -> Set Notes to: Vacant

3. COMMON AREA (Overrides User):
   IF Type is 'Meeting Room', 'Storage', 'Kitchen', etc.
   -> Set Notes to: Common Area
   (Note: Ignore any assigned users for these room types; they are just keyholders)

TARGET ROOMS: RM-A-101, RM-A-102, RM-A-103, RM-A-104, RM-A-105
EOF
chown ga:ga /home/ga/Desktop/occupancy_rules.txt

# Seed data via Python API
python3 << 'PYEOF'
import sys, json, time
sys.path.insert(0, "/workspace/scripts")
from cmdbuild_api import *

token = get_token()
if not token:
    print("ERROR: Could not authenticate to CMDBuild API", file=sys.stderr)
    sys.exit(1)

print("Authenticated to CMDBuild API")

# Find Room class
room_cls = find_class("Room", token)
if not room_cls:
    # Fallback search
    for c in list_classes(token):
        if "room" in c.get("description", "").lower():
            room_cls = c.get("_id")
            break
if not room_cls:
    print("ERROR: Could not find Room class", file=sys.stderr)
    sys.exit(1)

print(f"Using Room class: {room_cls}")

# Define the seeded rooms with DIRTY data
# We use Description to store the source of truth (Type/User)
# We use Notes to store the status (Agent must fix this)

rooms_to_seed = [
    {
        "Code": "RM-A-101",
        "Description": "Type: Office | User: John Smith",
        "Notes": "Vacant",  # WRONG - Should be Occupied
        "GroundTruth": "Occupied"
    },
    {
        "Code": "RM-A-102",
        "Description": "Type: Office | User: None",
        "Notes": "Occupied",  # WRONG - Should be Vacant
        "GroundTruth": "Vacant"
    },
    {
        "Code": "RM-A-103",
        "Description": "Type: Meeting Room | User: None",
        "Notes": "Vacant",  # WRONG - Should be Common Area
        "GroundTruth": "Common Area"
    },
    {
        "Code": "RM-A-104",
        "Description": "Type: Storage | User: B. Custodian",
        "Notes": "Occupied",  # WRONG - Storage is Common Area (Rule 3)
        "GroundTruth": "Common Area"
    },
    {
        "Code": "RM-A-105",
        "Description": "Type: Office | User: Alice Doe",
        "Notes": "Occupied",  # CORRECT - Preservation check
        "GroundTruth": "Occupied"
    }
]

# Create or Update rooms
created_ids = {}
for room in rooms_to_seed:
    # Check if exists
    cards = get_cards(room_cls, token, limit=5, filter_str=f"filter={{\"attribute\":{{\"simple\":{{\"attribute\":\"Code\",\"operator\":\"equal\",\"value\":[\"{room['Code']}\"]}}}}}}")
    
    attrs = {
        "Code": room["Code"],
        "Description": room["Description"],
        "Notes": room["Notes"]
    }
    
    if cards:
        card_id = cards[0]["_id"]
        update_card(room_cls, card_id, attrs, token)
        print(f"Updated {room['Code']}")
        created_ids[room["Code"]] = card_id
    else:
        card_id = create_card(room_cls, attrs, token)
        print(f"Created {room['Code']}")
        created_ids[room["Code"]] = card_id

# Save initial state for verification
with open("/tmp/room_audit_baseline.json", "w") as f:
    json.dump({
        "room_class": room_cls,
        "room_ids": created_ids,
        "seed_data": rooms_to_seed
    }, f)

print("Setup data seeded successfully.")
PYEOF

# Record start time
date +%s > /tmp/task_start_time.txt

# Launch Firefox
pkill -f firefox || true
sleep 1
su - ga -c "DISPLAY=:1 firefox '$OPENMAINT_URL' > /tmp/firefox_setup.log 2>&1 &"

# Wait for window
wait_for_window "firefox|mozilla|openmaint" 30
focus_firefox || true

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="