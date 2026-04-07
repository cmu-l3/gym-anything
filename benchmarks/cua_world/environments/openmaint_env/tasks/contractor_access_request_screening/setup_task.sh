#!/bin/bash
set -e
echo "=== Setting up Contractor Access Request Screening ==="

source /workspace/scripts/task_utils.sh

# Wait for OpenMaint to be ready
if ! wait_for_openmaint 240; then
    echo "ERROR: OpenMaint is not reachable"
    exit 1
fi

# Create the request file on the desktop
cat > /home/ga/Desktop/contractor_requests_2026-03-10.txt << 'EOF'
DATE: 2026-03-10
REQUESTS:

1. Vendor: Apex Elevators
   Task: Quarterly Hydraulic Check
   Location: Building A
   Security Instructions: Issue Key K-01

2. Vendor: Flow Plumbing
   Task: Restroom Flange Repair
   Location: Building B
   Security Instructions: None

3. Vendor: Spark Electrical
   Task: UPS Battery Replacement
   Location: Building C
   Security Instructions: Escort Required

4. Vendor: Unknown Inc
   Task: Window Washing
   Location: Building A
   Security Instructions: Exterior Only

5. Vendor: Bright Cleaners
   Task: Carpet Steam Clean
   Location: Building B
   Security Instructions: After-hours Sign-in
EOF
chown ga:ga /home/ga/Desktop/contractor_requests_2026-03-10.txt

# Seed Database
python3 << 'PYEOF'
import sys, json, os, time
sys.path.insert(0, "/workspace/scripts")
from cmdbuild_api import *

token = get_token()
if not token:
    print("ERROR: Could not authenticate to CMDBuild API", file=sys.stderr)
    sys.exit(1)

print("Authenticated to CMDBuild API")

# 1. Find Company/Vendor Class
vendor_cls = None
for pattern in ["^Company$", "^Vendor$", "^Supplier$", "BusinessPartner"]:
    found = find_class(pattern, token)
    if found:
        vendor_cls = found
        break

if not vendor_cls:
    print("WARNING: Could not find exact Vendor/Company class, defaulting to 'Company'")
    vendor_cls = "Company"

print(f"Using Vendor Class: {vendor_cls}")

# 2. Seed Vendors with Status
# We will use the 'Description' or 'Notes' field to store the Status if a specific Status field isn't easily found/writable.
# To be robust, we'll put it in Description: "Status: Active"

vendors_to_seed = [
    {"Name": "Apex Elevators", "Status": "Active"},
    {"Name": "Flow Plumbing", "Status": "Suspended"},
    {"Name": "Spark Electrical", "Status": "Active"},
    {"Name": "Bright Cleaners", "Status": "Active"}
    # Unknown Inc is intentionally NOT seeded
]

# Check if vendors exist, if not create them
existing_cards = get_cards(vendor_cls, token, limit=500)
existing_names = []

for card in existing_cards:
    # Handle different name fields (Description, Code, Name)
    name = card.get("Description", "") or card.get("Code", "")
    existing_names.append(name)

for v in vendors_to_seed:
    # Simple check to avoid duplicates if re-running
    already_exists = False
    for en in existing_names:
        if v["Name"] in en:
            already_exists = True
            break
    
    if not already_exists:
        data = {
            "Code": v["Name"].replace(" ", "_").upper(),
            "Description": v["Name"],
            "Notes": f"Status: {v['Status']}"  # Explicit status instruction
        }
        # Try to set a more visible description if possible
        data["Description"] = f"{v['Name']} - Status: {v['Status']}"
        
        create_card(vendor_cls, data, token)
        print(f"Created vendor: {v['Name']} ({v['Status']})")

# 3. Ensure Buildings Exist (Building A, B, C)
buildings_needed = ["Building A", "Building B", "Building C"]
existing_buildings = get_buildings(token)
existing_bld_names = [b.get("Description", "") for b in existing_buildings]

for b_name in buildings_needed:
    if not any(b_name in existing for existing in existing_bld_names):
        data = {
            "Code": b_name.replace(" ", "_").upper(),
            "Description": b_name
        }
        create_card("Building", data, token)
        print(f"Created building: {b_name}")

# 4. Record Initial Work Order Count (Baseline)
# Find maintenance class
wo_type, wo_cls = find_maintenance_class(token)
if not wo_cls:
    # Fallback if discovery fails
    wo_cls = "WorkOrder"
    wo_type = "card"

initial_count = count_records(wo_type, wo_cls, token)
print(f"Baseline WO Count: {initial_count}")

with open("/tmp/initial_wo_count.txt", "w") as f:
    f.write(str(initial_count))

with open("/tmp/wo_class_info.json", "w") as f:
    json.dump({"type": wo_type, "class": wo_cls}, f)

PYEOF

# Record start time
date +%s > /tmp/task_start_time.txt

# Setup Firefox
pkill -f firefox || true
sleep 1
su - ga -c "DISPLAY=:1 firefox '$OPENMAINT_URL' > /tmp/firefox_task.log 2>&1 &"

# Wait for window
wait_for_window "firefox|mozilla|openmaint" 40
focus_firefox || true

# Maximize
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

echo "=== Task Setup Complete ==="