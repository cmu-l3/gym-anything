#!/bin/bash
set -e
echo "=== Setting up erp_asset_synchronization_protocol ==="

source /workspace/scripts/task_utils.sh

if ! wait_for_openmaint 240; then
    echo "ERROR: OpenMaint is not reachable"
    exit 1
fi

# Generate the task data using Python and CMDBuild API
python3 << 'PYEOF'
import sys, json, os
sys.path.insert(0, "/workspace/scripts")
from cmdbuild_api import *

token = get_token()
if not token:
    print("ERROR: Could not authenticate to CMDBuild API", file=sys.stderr)
    sys.exit(1)

print("Authenticated to CMDBuild API")

# 1. DISCOVER CLASSES
# Find Asset/Equipment class
asset_cls = None
for pattern in [r"^Asset$", r"^Equipment$", r"CI", r"ConfigurationItem", r"Hardware"]:
    found = find_class(pattern, token)
    if found:
        asset_cls = found
        break
if not asset_cls:
    # Fallback to listing and guessing
    cls_list = list_classes(token)
    for c in cls_list:
        if "asset" in c.get("description", "").lower():
            asset_cls = c.get("_id")
            break
print(f"Asset Class: {asset_cls}")

# Find Ticket/Request class
ticket_type, ticket_cls = find_maintenance_class(token)
print(f"Ticket Class: {ticket_cls} (Type: {ticket_type})")

# 2. DISCOVER FIELDS
asset_attrs = get_class_attributes(asset_cls, token) if asset_cls else []
attr_map = {a.get("_id", ""): a for a in asset_attrs}

serial_field = None
status_field = None
desc_field = "Description"

for aname, ainfo in attr_map.items():
    low = aname.lower()
    if "serial" in low: serial_field = aname
    if "status" in low and "flow" not in low: status_field = aname

if not serial_field: serial_field = "SerialNumber" # Default guess

print(f"Fields: Serial={serial_field}, Status={status_field}")

# 3. SEED ASSETS
# We need to create specific assets for the scenario
# Asset 1: Standard update
# Asset 2: Write off
# Asset 3: Standard update
# Asset 4 & 5: Duplicate Serial Trap

assets_to_create = [
    {
        "Code": "EQ-SYNC-001", 
        "Description": "Dell Latitude 5520 Laptop", 
        serial_field: "SN-DELL-X10"
    },
    {
        "Code": "EQ-SYNC-002", 
        "Description": "HP LaserJet Pro Printer", 
        serial_field: "SN-HP-P20"
    },
    {
        "Code": "EQ-SYNC-003", 
        "Description": "Herman Miller Aeron Chair", 
        serial_field: "SN-HM-C55"
    },
    {
        "Code": "EQ-SYNC-DUP-A", 
        "Description": "Generic Monitor - Front Desk", 
        serial_field: "SN-DUP-999"
    },
    {
        "Code": "EQ-SYNC-DUP-B", 
        "Description": "Generic Monitor - Back Office", 
        serial_field: "SN-DUP-999"
    }
]

seeded_ids = {}
for data in assets_to_create:
    # Check if exists first to avoid double seeding on re-runs
    existing = get_cards(asset_cls, token, limit=1, filter_str=f"filter={{\"attribute\":{{\"simple\":{{\"attribute\":\"Code\",\"operator\":\"equal\",\"value\":\"{data['Code']}\"}}}}}}")
    if existing:
        cid = existing[0]["_id"]
        # Update to ensure clean state
        update_card(asset_cls, cid, data, token)
        seeded_ids[data["Code"]] = cid
    else:
        cid = create_card(asset_cls, data, token)
        seeded_ids[data["Code"]] = cid
    print(f"Seeded {data['Code']} -> {seeded_ids[data['Code']]}")

# 4. CREATE CSV FILE
csv_content = """AssetID,Description,SerialNumber,CostCenter,Status,CapDate
FA-100201,Dell Latitude 5520,SN-DELL-X10,CC-IT-OPS,ACTIVE,2024-01-15
FA-100202,HP LaserJet Pro,SN-HP-P20,CC-ADMIN,WRITTEN_OFF,2020-03-10
FA-100203,Herman Miller Chair,SN-HM-C55,CC-HR,ACTIVE,2023-11-05
FA-100204,Generic Monitor,SN-DUP-999,CC-IT-SUP,ACTIVE,2022-06-20
FA-100299,Ghost Asset,SN-MISSING,CC-VOID,ACTIVE,2024-01-01
"""

with open("/home/ga/Desktop/finance_fixed_assets.csv", "w") as f:
    f.write(csv_content)

os.system("chown ga:ga /home/ga/Desktop/finance_fixed_assets.csv")

# 5. SAVE BASELINE
baseline = {
    "asset_class": asset_cls,
    "ticket_class": ticket_cls,
    "ticket_type": ticket_type,
    "seeded_ids": seeded_ids,
    "serial_field": serial_field,
    "status_field": status_field,
    "trap_serial": "SN-DUP-999"
}

with open("/tmp/erp_baseline.json", "w") as f:
    json.dump(baseline, f)

PYEOF

# Record start time
date +%s > /tmp/task_start_time.txt

# Launch Browser
pkill -f firefox || true
sleep 1
su - ga -c "DISPLAY=:1 firefox '$OPENMAINT_URL' > /tmp/firefox_task.log 2>&1 &"

if ! wait_for_window "firefox|mozilla|openmaint|cmdbuild" 40; then
    echo "WARNING: Firefox window not detected"
fi

focus_firefox || true

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="