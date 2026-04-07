#!/bin/bash
set -e
echo "=== Setting up extract_section_to_document task ==="

source /workspace/scripts/task_utils.sh

# 1. Kill any running ReqView instances
pkill -f "reqview" 2>/dev/null || true
sleep 2

# 2. Setup a fresh project copy
PROJECT_PATH=$(setup_task_project "extract_section")
echo "Task project path: $PROJECT_PATH"

# 3. Inject "Security" section into SRS.json
# We use a python script to safely modify the JSON structure
SRS_JSON="$PROJECT_PATH/documents/SRS.json"

if [ ! -f "$SRS_JSON" ]; then
    echo "ERROR: SRS.json not found at $SRS_JSON"
    exit 1
fi

python3 << PYEOF
import json
import uuid
import sys
import os

srs_path = "$SRS_JSON"
print(f"Injecting data into {srs_path}")

try:
    with open(srs_path, 'r') as f:
        srs = json.load(f)
except Exception as e:
    print(f"Error loading JSON: {e}")
    sys.exit(1)

# Create the Security section structure
security_section = {
    "id": "SEC_HEAD",
    "guid": str(uuid.uuid4()),
    "heading": "Security",
    "children": [
        {
            "id": "SEC_01",
            "guid": str(uuid.uuid4()),
            "text": "All data at rest shall be encrypted using AES-256.",
            "status": "Draft",
            "type": "NFR"
        },
        {
            "id": "SEC_02",
            "guid": str(uuid.uuid4()),
            "text": "All external communications shall be secured using TLS 1.3 or higher.",
            "status": "Draft",
            "type": "NFR"
        },
        {
            "id": "SEC_03",
            "guid": str(uuid.uuid4()),
            "text": "User passwords shall be hashed using Argon2 with a minimum work factor of 16.",
            "status": "Draft",
            "type": "NFR"
        }
    ]
}

# Inject at the end of the document data
if 'data' not in srs:
    srs['data'] = []

srs['data'].append(security_section)

# Update file
with open(srs_path, 'w') as f:
    json.dump(srs, f, indent=2)

print("Injection complete.")
PYEOF

# 4. Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# 5. Launch ReqView with the project
launch_reqview_with_project "$PROJECT_PATH"

# 6. Prepare UI
dismiss_dialogs
maximize_window

# 7. Open SRS document so the agent sees the "Security" section immediately
# This reduces searching time and makes the starting state clear
open_srs_document
sleep 2

# 8. Scroll to bottom to ensure "Security" might be visible (it was appended)
# Using PageDown a few times
for i in {1..5}; do
    DISPLAY=:1 xdotool key Page_Down
    sleep 0.2
done

# 9. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="