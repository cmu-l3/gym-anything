#!/bin/bash
set -e
echo "=== Setting up manage_lifecycle_states task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Wait for Nuxeo to be fully ready
wait_for_nuxeo 120

# Python script to ensure documents exist and reset their lifecycle states to 'project'
# This handles the case where a previous run left them in 'approved' or 'obsolete' state.
echo "Preparing document states..."
python3 << 'PYEOF'
import requests
import json
import sys

base = "http://localhost:8080/nuxeo/api/v1"
auth = ("Administrator", "Administrator")
headers = {"Content-Type": "application/json"}

# Define documents to check/reset
docs = {
    "Annual-Report-2023": "/default-domain/workspaces/Projects/Annual-Report-2023",
    "Project-Proposal": "/default-domain/workspaces/Projects/Project-Proposal",
    "Q3-Status-Report": "/default-domain/workspaces/Projects/Q3-Status-Report",
    "Contract-Template": "/default-domain/workspaces/Templates/Contract-Template"
}

initial_states = {}

for name, path in docs.items():
    url = f"{base}/path{path}"
    try:
        r = requests.get(url, auth=auth, headers=headers)
        if r.status_code == 404:
            print(f"WARNING: Document {name} not found. Setup script should have created it.")
            initial_states[name] = "missing"
            continue
            
        data = r.json()
        current_state = data.get("state", "unknown")
        print(f"  {name}: {current_state}")
        
        # If not in 'project' state, try to reset it
        if current_state != "project":
            print(f"  Resetting {name} to 'project' state...")
            # 'backToProject' is the standard transition from approved/obsolete to project in default Nuxeo lifecycle
            op_url = f"{url}/@op/Document.FollowLifecycleTransition"
            r_reset = requests.post(op_url, auth=auth, headers=headers, json={"params": {"value": "backToProject"}})
            
            if r_reset.status_code in [200, 204]:
                initial_states[name] = "project"
            else:
                print(f"  FAILED to reset {name}: HTTP {r_reset.status_code}")
                initial_states[name] = current_state
        else:
            initial_states[name] = "project"
            
    except Exception as e:
        print(f"Error checking {name}: {e}")
        initial_states[name] = "error"

# Save initial states for verifier to check against later
with open("/tmp/initial_lifecycle_states.json", "w") as f:
    json.dump(initial_states, f)
PYEOF

# Ensure Firefox is open and logged in
open_nuxeo_url "$NUXEO_URL/login.jsp" 8

# Check if login is needed
PAGE_TITLE=$(DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
    xdotool getactivewindow getwindowname 2>/dev/null || echo "")
if ! echo "$PAGE_TITLE" | grep -q " - Nuxeo Platform"; then
    nuxeo_login
fi

# Navigate to Projects workspace
sleep 2
navigate_to "$NUXEO_UI/#!/browse/default-domain/workspaces/Projects"
sleep 4

# Take initial screenshot for evidence
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="