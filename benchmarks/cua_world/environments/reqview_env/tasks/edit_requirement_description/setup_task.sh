#!/bin/bash
set -e
echo "=== Setting up edit_requirement_description task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Kill any running ReqView instances
pkill -f "reqview" 2>/dev/null || true
sleep 2

# 3. Setup a fresh project copy
PROJECT_NAME="edit_req_desc_project"
PROJECT_PATH=$(setup_task_project "$PROJECT_NAME")
echo "Project path: $PROJECT_PATH"

SRS_PATH="$PROJECT_PATH/documents/SRS.json"

# 4. Identify Target Requirement (SRS-5) and backup initial state
# We use Python to parse the JSON, find SRS-5, and save metadata.
# If SRS-5 doesn't exist, we fallback to the first valid requirement.
python3 << PYEOF
import json
import sys
import os

srs_path = "$SRS_PATH"
meta_path = "/tmp/task_metadata.json"
initial_path = "/tmp/srs_initial.json"

try:
    with open(srs_path, 'r') as f:
        data = json.load(f)
        
    # Save initial state for diffing later
    with open(initial_path, 'w') as f:
        json.dump(data, f)
        
    # Find SRS-5 (id: 5) or fallback
    target_id = "5"
    target_obj = None
    
    def find_req(items, tid):
        for item in items:
            if str(item.get('id', '')) == tid:
                return item
            if 'children' in item:
                found = find_req(item['children'], tid)
                if found: return found
        return None
        
    def find_first_leaf(items):
        for item in items:
            if 'children' not in item or not item['children']:
                return item
            found = find_first_leaf(item['children'])
            if found: return found
        return None

    target_obj = find_req(data.get('data', []), target_id)
    
    # Fallback if SRS-5 missing
    if not target_obj:
        print(f"SRS-{target_id} not found, finding fallback...")
        target_obj = find_first_leaf(data.get('data', []))
        if target_obj:
            target_id = str(target_obj.get('id'))
            
    if target_obj:
        print(f"Target Requirement: SRS-{target_id}")
        initial_desc = target_obj.get('description', '') or target_obj.get('text', '')
        
        meta = {
            "target_id": target_id,
            "target_doc": "SRS",
            "initial_description_length": len(initial_desc),
            "srs_path": srs_path
        }
        with open(meta_path, 'w') as f:
            json.dump(meta, f)
    else:
        print("ERROR: No requirements found in SRS document")
        sys.exit(1)

except Exception as e:
    print(f"Setup Error: {e}")
    sys.exit(1)
PYEOF

# 5. Launch ReqView with the project
echo "Launching ReqView..."
launch_reqview_with_project "$PROJECT_PATH"

# 6. Configure UI state
sleep 5
dismiss_dialogs
maximize_window

# 7. Open the SRS document specifically so the agent sees the table
# This function clicks 'SRS' in the project tree
open_srs_document

# 8. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="