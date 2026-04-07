#!/bin/bash
set -e
echo "=== Setting up lookup_type_configuration ==="

source /workspace/scripts/task_utils.sh

# Wait for OpenMaint to be ready
if ! wait_for_openmaint 240; then
    echo "ERROR: OpenMaint is not reachable"
    exit 1
fi

# Create the requirements file on the desktop
cat > /home/ga/Desktop/lookup_requirements.txt << 'EOF'
OPENMAINT LOOKUP TYPE CONFIGURATION
====================================
Date: 2026-01-15
Requested by: Director of Maintenance Operations
Priority: High — Required before CMMS go-live

Please create the following three (3) lookup types in the
Administration module. Each value must use the exact Code
and Description shown below. Values should appear in the
listed order (first listed = index 1).

-------------------------------------------------------------
LOOKUP TYPE 1: MaintenanceShift
Description: Work shift classifications for maintenance scheduling
-------------------------------------------------------------
 #  | Code | Description
 1  | DAY  | Day Shift
 2  | EVE  | Evening Shift
 3  | NGT  | Night Shift
 4  | WKD  | Weekend Shift

-------------------------------------------------------------
LOOKUP TYPE 2: CostCenter
Description: Maintenance cost allocation centers
-------------------------------------------------------------
 #  | Code | Description
 1  | CC100 | General Maintenance
 2  | CC200 | HVAC Systems
 3  | CC300 | Electrical Systems
 4  | CC400 | Plumbing
 5  | CC500 | Grounds and Exterior

-------------------------------------------------------------
LOOKUP TYPE 3: FailureCategory
Description: Root cause failure classification for work orders
-------------------------------------------------------------
 #  | Code | Description
 1  | MECH | Mechanical Failure
 2  | ELEC | Electrical Failure
 3  | PLMB | Plumbing Failure
 4  | STRC | Structural Damage
 5  | ENVR | Environmental Issue
 6  | OTHR | Other / Unclassified

-------------------------------------------------------------
IMPORTANT: Do NOT modify or delete any existing lookup types.
-------------------------------------------------------------
EOF

chown ga:ga /home/ga/Desktop/lookup_requirements.txt

# Record baseline state (existing lookup types) using Python API
python3 << 'PYEOF'
import sys, json, os
sys.path.insert(0, "/workspace/scripts")
from cmdbuild_api import *

token = get_token()
if not token:
    print("ERROR: Could not authenticate to CMDBuild API", file=sys.stderr)
    sys.exit(1)

# Get all current lookup types to establish baseline count
# Note: The API helper `list_classes` lists classes/processes, but lookup types 
# are accessed via /lookup_types. We'll use the generic api function.
resp = api("GET", "lookup_types?limit=500", token)
lookup_types = resp.get("data", []) if resp else []
lookup_ids = [lt.get("_id") for lt in lookup_types]

# Specifically check "Priority" lookup as a reference for preservation
priority_values = get_lookup_values("Priority", token)
priority_baseline = [
    {"code": v.get("Code"), "desc": v.get("Description")} 
    for v in priority_values
]

baseline = {
    "total_count": len(lookup_types),
    "existing_ids": lookup_ids,
    "priority_baseline": priority_baseline,
    "priority_count": len(priority_values)
}

save_baseline("/tmp/lookup_baseline.json", baseline)
print(f"Baseline saved. Found {len(lookup_types)} existing lookup types.")
PYEOF

# Record start time
date +%s > /tmp/task_start_time.txt

# Launch Firefox to login page
pkill -f firefox || true
sleep 1
su - ga -c "DISPLAY=:1 firefox '$OPENMAINT_URL' > /tmp/firefox_task.log 2>&1 &"

if ! wait_for_window "firefox|mozilla|openmaint" 40; then
    echo "WARNING: Firefox window not detected"
fi

focus_firefox || true

# Capture initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="