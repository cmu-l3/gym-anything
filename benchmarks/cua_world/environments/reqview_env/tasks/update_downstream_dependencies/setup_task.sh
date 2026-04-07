#!/bin/bash
set -e
echo "=== Setting up update_downstream_dependencies task ==="

source /workspace/scripts/task_utils.sh

# 1. Kill any running ReqView instances
pkill -f "reqview" 2>/dev/null || true
sleep 2

# 2. Setup a fresh project copy
PROJECT_NAME="update_dependencies_project"
PROJECT_PATH=$(setup_task_project "$PROJECT_NAME")
echo "Task project path: $PROJECT_PATH"

# 3. Create the Change Request file on Desktop
cat > /home/ga/Desktop/ChangeRequest_CR105.txt << EOF
CHANGE REQUEST: CR-105
DATE: $(date +%Y-%m-%d)
STATUS: Approved

DESCRIPTION:
Market analysis indicates our response time targets are too slow.
The Stakeholder Need NEEDS-05 ("Response Time") has been updated.
Old Value: 2 seconds
New Value: 500 milliseconds

ACTION REQUIRED:
1. Locate NEEDS-05 and identify linked System Requirements.
2. Update the linked System Requirement (SRS-12) to reflect the new 500ms target.
3. Add a comment to the updated requirement: "Updated per CR-105".
EOF
chown ga:ga /home/ga/Desktop/ChangeRequest_CR105.txt

# 4. Inject specific Data into the Project JSONs to guarantee the scenario exists.
# We need NEEDS-05 to exist and SRS-12 to exist and be linked.

python3 << PYEOF
import json
import os
import sys

project_path = "$PROJECT_PATH"
needs_file = os.path.join(project_path, "documents", "NEEDS.json")
srs_file = os.path.join(project_path, "documents", "SRS.json")

def load_json(path):
    with open(path, 'r') as f:
        return json.load(f)

def save_json(path, data):
    with open(path, 'w') as f:
        json.dump(data, f, indent=2)

# --- Update NEEDS.json ---
try:
    needs_doc = load_json(needs_file)
    # create NEEDS-05
    needs_05 = {
        "id": "05", 
        "heading": "System Response Time", 
        "text": "<p>The system shall respond to user inputs within 2 seconds.</p>", 
        "status": "Accepted"
    }
    
    # Insert at top of data for visibility
    if 'data' not in needs_doc: needs_doc['data'] = []
    # Check if exists, replace or append
    existing = next((i for i, x in enumerate(needs_doc['data']) if x.get('id') == "05"), None)
    if existing is not None:
        needs_doc['data'][existing] = needs_05
    else:
        needs_doc['data'].insert(0, needs_05)
    
    save_json(needs_file, needs_doc)
    print("Updated NEEDS.json with NEEDS-05")

except Exception as e:
    print(f"Error updating NEEDS: {e}")

# --- Update SRS.json ---
try:
    srs_doc = load_json(srs_file)
    
    # Create SRS-12 linked to NEEDS-05
    srs_12 = {
        "id": "12",
        "heading": "Maximum Latency",
        "text": "<p>The system shall have a maximum latency of 2 seconds for all operations.</p>",
        "status": "Draft",
        "links": [
            {
                "docId": "NEEDS",
                "reqId": "05",
                "type": "satisfies"
            }
        ]
    }
    
    # Insert at top of data
    if 'data' not in srs_doc: srs_doc['data'] = []
    existing = next((i for i, x in enumerate(srs_doc['data']) if x.get('id') == "12"), None)
    if existing is not None:
        srs_doc['data'][existing] = srs_12
    else:
        srs_doc['data'].insert(0, srs_12)
        
    save_json(srs_file, srs_doc)
    print("Updated SRS.json with SRS-12 and trace link")

except Exception as e:
    print(f"Error updating SRS: {e}")

PYEOF

# 5. Launch ReqView
launch_reqview_with_project "$PROJECT_PATH"

sleep 5
dismiss_dialogs
maximize_window

# 6. Open the text editor with the change request so the agent sees it immediately
su - ga -c "DISPLAY=:1 xdg-open /home/ga/Desktop/ChangeRequest_CR105.txt"
sleep 2
# Tile windows: ReqView left, Text Editor right (approximate)
# Focus ReqView first
DISPLAY=:1 wmctrl -a "ReqView"
DISPLAY=:1 wmctrl -r "ReqView" -e 0,0,0,960,1080
# Focus Text Editor (gedit or similar)
DISPLAY=:1 wmctrl -a "ChangeRequest" || true
DISPLAY=:1 wmctrl -r :ACTIVE: -e 0,960,0,960,1080 || true

# Record start time
date +%s > /tmp/task_start_time.txt

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="