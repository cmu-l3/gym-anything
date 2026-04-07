#!/bin/bash
set -e
echo "=== Setting up BMS Firmware Upgrade Task ==="

source /workspace/scripts/task_utils.sh

# Wait for OpenMaint to be ready
if ! wait_for_openmaint 240; then
    echo "ERROR: OpenMaint is not reachable"
    exit 1
fi

# Create the Security Bulletin on the Desktop
cat > /home/ga/Desktop/security_bulletin_cve_2026.txt << 'EOF'
SECURITY BULLETIN: CVE-2026-9912
severity: CRITICAL
Date: 2026-03-08

VULNERABILITY SUMMARY:
A remote code execution vulnerability has been identified in the web interface of Tridium JACE 8000 controllers running firmware versions prior to 4.12.

REQUIRED ACTION:
Immediate firmware upgrade is required for all facility-owned equipment.

TARGET SCOPE:
- Equipment Type: Building Management Controller
- Model: Tridium JACE 8000
- Status: Active units only (Retired/Storage units can be patched later)
- Ownership: OWNED units only. (Leased units are managed by the vendor - DO NOT TOUCH).

WORK ORDER INSTRUCTIONS:
Create a Corrective Maintenance Work Order for each eligible unit.
- Description: "Firmware Upgrade - CVE-2026-9912"
- Priority: Critical / High
- Category: System Maintenance / Security
- Due Date: 2026-06-15

Authorized by: CISO Office
EOF
chown ga:ga /home/ga/Desktop/security_bulletin_cve_2026.txt

# Seed Data via Python API
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
asset_cls = None
# Try to find a generic "Asset" or "Device" class
for pattern in [r"^Asset$", r"^Device$", r"^Equipment$", r"^CI$", r"InternalEquipment"]:
    found = find_class(pattern, token)
    if found:
        asset_cls = found
        break

# Fallback
if not asset_cls:
    print("WARNING: Could not find specific Asset class, using first available CI class or creating generic")
    # List all classes and pick one that looks like a CI
    classes = list_classes(token)
    for c in classes:
        if c.get("type") == "class" and not c.get("superclass"): 
             # Just picking a non-process class if possible, or defaulting
             pass
    # For the openmaint env, "Asset" or "InternalEquipment" usually exists.
    # We will assume "Asset" or "Equipment" based on previous env usage.
    asset_cls = "Asset" # forceful fallback if detection fails, assuming env standard

print(f"Using Asset Class: {asset_cls}")

# 2. Define the fleet of controllers
# We will use the Description field to store the criteria if specific fields don't exist,
# ensuring the agent can filter by text search.
# Format: "BMS Controller - [Model] - [Ownership] - [Location]"

fleet = [
    {
        "code": "CTRL-J8-001",
        "desc": "BMS Controller - Tridium JACE 8000 - Owned - Main Plant",
        "status": "Active",
        "eligible": True
    },
    {
        "code": "CTRL-J8-002",
        "desc": "BMS Controller - Tridium JACE 8000 - Owned - East Wing",
        "status": "Active",
        "eligible": True
    },
    {
        "code": "CTRL-J8-003",
        "desc": "BMS Controller - Tridium JACE 8000 - Leased - Vendor Managed",
        "status": "Active",
        "eligible": False # Leased
    },
    {
        "code": "CTRL-J9-001",
        "desc": "BMS Controller - Tridium JACE 9000 - Owned - North Wing",
        "status": "Active",
        "eligible": False # Wrong Model
    },
    {
        "code": "CTRL-J8-OLD",
        "desc": "BMS Controller - Tridium JACE 8000 - Owned - Spare Room",
        "status": "Retired", # or Inactive
        "eligible": False # Inactive
    },
    {
        "code": "CTRL-J8-004",
        "desc": "BMS Controller - Tridium JACE 8000 - Owned - Penthouse",
        "status": "Active",
        "eligible": True
    }
]

seeded_ids = {}

for item in fleet:
    # Check if exists
    existing = get_cards(asset_cls, token, limit=1, filter_str=f"filter={{\"attribute\":{{\"simple\":{{\"attribute\":\"Code\",\"operator\":\"equal\",\"value\":\"{item['code']}\"}}}}}}")
    
    card_data = {
        "Code": item["code"],
        "Description": item["desc"],
        "_is_active": (item["status"] == "Active")
    }
    
    if existing:
        print(f"Updating existing asset {item['code']}")
        card_id = existing[0]["_id"]
        update_card(asset_cls, card_id, card_data, token)
    else:
        print(f"Creating new asset {item['code']}")
        card_id = create_card(asset_cls, card_data, token)
    
    seeded_ids[item["code"]] = {
        "id": card_id, 
        "eligible": item["eligible"]
    }

# Save baseline for export script
baseline = {
    "asset_class": asset_cls,
    "seeded_assets": seeded_ids
}
save_baseline("/tmp/bms_task_baseline.json", baseline)

PYEOF

# Record start time
date +%s > /tmp/task_start_time.txt

# Launch Firefox
pkill -f firefox || true
sleep 1
su - ga -c "DISPLAY=:1 firefox '$OPENMAINT_URL' > /tmp/firefox_task.log 2>&1 &"

# Wait for window
wait_for_window "firefox|mozilla|openmaint" 40
focus_firefox

# Capture initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="