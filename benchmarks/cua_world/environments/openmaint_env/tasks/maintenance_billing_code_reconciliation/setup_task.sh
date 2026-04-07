#!/bin/bash
set -e
echo "=== Setting up maintenance_billing_code_reconciliation ==="

source /workspace/scripts/task_utils.sh

# Ensure OpenMaint is reachable
if ! wait_for_openmaint 240; then
    echo "ERROR: OpenMaint is not reachable"
    exit 1
fi

# Create the CSV mapping file on Desktop
cat > /home/ga/Desktop/billing_code_map.csv << 'CSVEOF'
Room,Department,BillingCode
RM-101,Finance,FIN-900
RM-102,Human Resources,HR-200
RM-103,Information Technology,IT-550
RM-104,Executive Suite,EXEC-100
RM-201,Sales,SAL-300
RM-202,Marketing,MKT-400
CSVEOF
chown ga:ga /home/ga/Desktop/billing_code_map.csv

# Seed Work Orders using Python API
python3 << 'PYEOF'
import sys, json, os, time
sys.path.insert(0, "/workspace/scripts")
from cmdbuild_api import *

token = get_token()
if not token:
    print("ERROR: Could not authenticate to CMDBuild API", file=sys.stderr)
    sys.exit(1)

print("Authenticated to CMDBuild API")

# Find Maintenance Class (Process or Card)
# We prioritize "WorkOrder" or "CorrectiveMaintenance"
wo_type, wo_cls = find_maintenance_class(token)
if not wo_cls:
    print("ERROR: Could not find WorkOrder/Maintenance class", file=sys.stderr)
    sys.exit(1)
print(f"Using class: {wo_cls} ({wo_type})")

# Define records to seed
seed_data = [
    {
        "Code": "WO-BILL-001", 
        "Description": "Leaking pipe in RM-101 ceiling tile damage",
        "Notes": "Technician: John Doe"
    },
    {
        "Code": "WO-BILL-002", 
        "Description": "Network port installation in RM-103 for new server",
        "Notes": "Technician: Jane Smith"
    },
    {
        "Code": "WO-BILL-003", 
        "Description": "Light ballast replacement in Main Hallway near elevator",
        "Notes": "Technician: Bob Jones"
    },
    {
        "Code": "WO-BILL-004", 
        "Description": "Thermostat adjustment request for RM-102 too cold",
        "Notes": "Technician: Alice Brown"
    },
    {
        "Code": "WO-BILL-005", 
        "Description": "Warranty repair on HVAC Unit 3 - Compressor failure",
        "Notes": "Technician: Vendor Service"
    },
    {
        "Code": "WO-BILL-006", 
        "Description": "Executive chair repair in RM-104 caster broken",
        "Notes": "Technician: Mike White"
    }
]

created_ids = {}

# Create records
for item in seed_data:
    # Check if exists and delete if so (cleanup from previous runs)
    existing = get_cards(wo_cls, token, limit=1, filter_str=f"filter={{\"attribute\":{{\"simple\":{{\"attribute\":\"Code\",\"operator\":\"equal\",\"value\":[\"{item['Code']}\"]}}}}}}")
    if existing:
        print(f"Deleting existing {item['Code']}...")
        delete_card(wo_cls, existing[0]['_id'], token)

    # Create new
    print(f"Creating {item['Code']}...")
    try:
        if wo_type == "process":
            # For processes, we might need minimal activity handling, but creating instance is usually enough for visibility
            pid = create_process_instance(wo_cls, item, token)
            if pid: created_ids[item['Code']] = pid
        else:
            cid = create_card(wo_cls, item, token)
            if cid: created_ids[item['Code']] = cid
    except Exception as e:
        print(f"Failed to create {item['Code']}: {e}")

# Save baseline for export script
baseline = {
    "wo_type": wo_type,
    "wo_cls": wo_cls,
    "ids": created_ids
}
save_baseline("/tmp/billing_reconcile_baseline.json", baseline)
print("Baseline saved.")
PYEOF

# Record start time
date +%s > /tmp/task_start_time.txt

# Launch Firefox to OpenMaint
pkill -f firefox || true
sleep 1
su - ga -c "DISPLAY=:1 firefox '$OPENMAINT_URL' > /tmp/firefox.log 2>&1 &"

# Wait for window and maximize
if wait_for_window "firefox" 60; then
    focus_firefox
    sleep 2
    # Ensure URL is loaded if browser just opened empty
    su - ga -c "DISPLAY=:1 xdotool key ctrl+l"
    sleep 0.5
    su - ga -c "DISPLAY=:1 xdotool type '$OPENMAINT_URL'"
    su - ga -c "DISPLAY=:1 xdotool key Return"
fi

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="