#!/bin/bash
set -e
echo "=== Setting up branch_prune_variant task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Kill any running ReqView instances
pkill -f "reqview" 2>/dev/null || true
sleep 2

# Set up a fresh copy of the example project
PROJECT_PATH=$(setup_task_project "branch_prune")
echo "Task project path: $PROJECT_PATH"

# Ensure the "Log Files" section exists in the SRS document
# We inject it if missing so the agent has something specific to prune
SRS_JSON="$PROJECT_PATH/documents/SRS.json"

python3 << PYEOF
import json
import sys
import uuid

srs_path = "$SRS_JSON"
target_section = "Log Files"

try:
    with open(srs_path, 'r') as f:
        doc = json.load(f)

    # Check if section already exists
    def find_section(items, name):
        for item in items:
            # Check text (often HTML wrapped) or heading
            txt = item.get('heading', '') or item.get('text', '')
            if name in txt:
                return True
            if 'children' in item:
                if find_section(item['children'], name):
                    return True
        return False

    if not find_section(doc.get('data', []), target_section):
        print(f"Injecting '{target_section}' section...")
        
        # Create a section with some child requirements
        new_section = {
            "id": "LOGS", 
            "heading": target_section,
            "children": [
                {
                    "id": "LOGS-1",
                    "text": "The system shall maintain a rotating log of the last 1000 events.",
                    "status": "Approved"
                },
                {
                    "id": "LOGS-2", 
                    "text": "Log files shall be encrypted at rest.",
                    "status": "Proposed"
                }
            ]
        }
        
        # Add to the end of the document
        if 'data' not in doc:
            doc['data'] = []
        doc['data'].append(new_section)
        
        with open(srs_path, 'w') as f:
            json.dump(doc, f, indent=2)
        print("Injection complete.")
    else:
        print(f"'{target_section}' section already exists.")

except Exception as e:
    print(f"Error modifying SRS: {e}")
    # Don't fail the setup, we'll try to proceed
    pass
PYEOF

# Launch ReqView with the project
launch_reqview_with_project "$PROJECT_PATH"

sleep 5

# Dismiss dialogs and maximize
dismiss_dialogs
maximize_window

# Record initial state screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="