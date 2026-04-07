#!/bin/bash
set -e
echo "=== Setting up power_dependency_mapping ==="

source /workspace/scripts/task_utils.sh

# Wait for OpenMaint to be ready
if ! wait_for_openmaint 300; then
    echo "ERROR: OpenMaint is not reachable"
    exit 1
fi

# Record start time
date +%s > /tmp/task_start_time.txt

# Create the topology text file on the desktop
cat > /home/ga/Desktop/power_topology.txt << 'EOF'
POWER DISTRIBUTION TOPOLOGY — BUILDING A
==========================================
Post-Incident Documentation Requirement
Date: 2026-03-08
Priority: URGENT

Following the cascading power failure, all electrical infrastructure dependencies 
must be recorded in OpenMaint immediately.

ELECTRICAL DISTRIBUTION CHAIN
------------------------------

1. Main Transformer (ELEC-XFMR-001) 480V/208V
   └── feeds → Main Switchgear (ELEC-SWGR-001)

2. Main Switchgear (ELEC-SWGR-001)
   ├── feeds → Distribution Panel Floor 1 (ELEC-DP-001)
   ├── feeds → Distribution Panel Floor 2 (ELEC-DP-002)
   └── feeds → Automatic Transfer Switch (ELEC-ATS-001)

3. Automatic Transfer Switch (ELEC-ATS-001)
   └── feeds → UPS Server Room (ELEC-UPS-001)

TOTAL RELATIONS TO CREATE: 5

INSTRUCTIONS:
- Open each source CI in OpenMaint
- Use the Relations tab to create a link to the destination CI
- Use whatever CI-to-CI relation domain is available (e.g., "includes", "connected to")
EOF
chown ga:ga /home/ga/Desktop/power_topology.txt
chmod 644 /home/ga/Desktop/power_topology.txt

# Python script to seed the CIs and record baseline
python3 << 'PYEOF'
import sys, json, os
sys.path.insert(0, "/workspace/scripts")
from cmdbuild_api import *

token = get_token()
if not token:
    print("ERROR: Could not authenticate to CMDBuild API", file=sys.stderr)
    sys.exit(1)

print("Authenticated to CMDBuild API")

# 1. Find a suitable CI class
asset_cls = None
# Try specific classes first
for candidate in ["Asset", "CI", "ConfigurationItem", "Device", "Equipment"]:
    if find_class(f"^{candidate}$", token):
        asset_cls = candidate
        break

# Fallback to broad search
if not asset_cls:
    all_classes = list_classes(token)
    for c in all_classes:
        name = c.get("_id", "")
        if "asset" in name.lower() or "ci" in name.lower():
            asset_cls = name
            break

if not asset_cls:
    print("ERROR: Could not find a suitable Asset/CI class", file=sys.stderr)
    sys.exit(1)

print(f"Using Asset class: {asset_cls}")

# 2. Define the 6 CIs
cis_to_create = [
    {"Code": "ELEC-XFMR-001", "Description": "Main Step-Down Transformer 480V/208V"},
    {"Code": "ELEC-SWGR-001", "Description": "Main Electrical Switchgear Panel"},
    {"Code": "ELEC-DP-001", "Description": "Distribution Panel - Floor 1"},
    {"Code": "ELEC-DP-002", "Description": "Distribution Panel - Floor 2"},
    {"Code": "ELEC-ATS-001", "Description": "Automatic Transfer Switch"},
    {"Code": "ELEC-UPS-001", "Description": "Uninterruptible Power Supply - Server Room"}
]

# 3. Create CIs and record IDs
created_cis = {}
for ci in cis_to_create:
    # Check if exists, delete if so to ensure clean slate (no existing relations)
    existing = get_cards(asset_cls, token, filter_str=f"filter={{\"attribute\":{{\"simple\":{{\"attribute\":\"Code\",\"operator\":\"equal\",\"value\":[\"{ci['Code']}\"]}}}}}}")
    if existing:
        for old in existing:
            # Delete old card to remove old relations
            print(f"Deleting existing card {old.get('Code')}")
            delete_card(asset_cls, old.get("_id"), token)
    
    # Create new
    print(f"Creating {ci['Code']}...")
    new_id = create_card(asset_cls, ci, token)
    if new_id:
        created_cis[ci['Code']] = new_id
    else:
        print(f"ERROR: Failed to create {ci['Code']}")

# 4. Save baseline for verifier
baseline = {
    "asset_class": asset_cls,
    "ci_map": created_cis,
    "ci_codes": cis_to_create
}

with open("/tmp/pdm_baseline.json", "w") as f:
    json.dump(baseline, f, indent=2)

print("Baseline saved to /tmp/pdm_baseline.json")
PYEOF

# Start Firefox
echo "Starting Firefox..."
pkill -f firefox || true
sleep 1
su - ga -c "DISPLAY=:1 firefox '$OPENMAINT_URL' > /tmp/firefox_task.log 2>&1 &"

# Wait for window and maximize
wait_for_window "firefox|mozilla" 60
focus_firefox || true

# Capture initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="