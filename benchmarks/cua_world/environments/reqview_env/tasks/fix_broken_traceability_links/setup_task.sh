#!/bin/bash
echo "=== Setting up fix_broken_traceability_links task ==="

source /workspace/scripts/task_utils.sh

# Kill any running ReqView
pkill -f "reqview" 2>/dev/null || true
sleep 2

# Set up a fresh copy of the example project for this task
PROJECT_PATH=$(setup_task_project "fix_broken_links")
echo "Task project path: $PROJECT_PATH"

SRS_JSON="$PROJECT_PATH/documents/SRS.json"

# Inject broken links into the SRS document using Python
# We will inject links to "LEGACY" document which doesn't exist.
if [ -f "$SRS_JSON" ]; then
    python3 << PYEOF
import json
import sys
import random

srs_path = "$SRS_JSON"

try:
    with open(srs_path, 'r') as f:
        srs = json.load(f)
except Exception as e:
    print(f"ERROR reading SRS.json: {e}", file=sys.stderr)
    sys.exit(1)

def inject_link(item, doc_id, req_id):
    if 'links' not in item:
        item['links'] = []
    
    # Check if link already exists
    for link in item['links']:
        if link.get('docId') == doc_id and link.get('reqId') == req_id:
            return
            
    # Add broken link
    item['links'].append({
        "docId": doc_id,
        "reqId": req_id,
        "type": "trace"
    })
    print(f"Injected broken link to {doc_id}-{req_id} into requirement {item.get('id')}")

# We want to inject into:
# 1. A requirement early in the doc (e.g., SRS-6 or SRS-10)
# 2. A requirement later in the doc (e.g., SRS-22 or SRS-45)
# Note: IDs in JSON are strings.

targets_found = 0
target_ids = []

def traverse_and_inject(items):
    global targets_found
    for item in items:
        # Skip sections (heading objects usually don't have links in this context, but requirements do)
        # In ReqView JSON, text is often in 'text' or 'description'. 
        
        # Heuristic: Inject into the 5th and 15th leaf nodes we find
        if 'children' in item:
            traverse_and_inject(item['children'])
        else:
            # It's a leaf requirement
            targets_found += 1
            if targets_found == 5:
                inject_link(item, "LEGACY", "404")
                target_ids.append(item.get('id'))
            elif targets_found == 15:
                inject_link(item, "LEGACY", "500")
                target_ids.append(item.get('id'))

traverse_and_inject(srs.get('data', []))

if len(target_ids) < 2:
    print("WARNING: Could not find enough requirements to inject links")

with open(srs_path, 'w') as f:
    json.dump(srs, f, indent=2)

print(f"Injection complete. Modified requirements: {target_ids}")
PYEOF
else
    echo "ERROR: SRS.json not found at $SRS_JSON"
    exit 1
fi

# Launch ReqView with the project
launch_reqview_with_project "$PROJECT_PATH"

sleep 5

# Dismiss any dialogs
dismiss_dialogs

# Maximize window
maximize_window

# Open the SRS document explicitly
open_srs_document

# Record task start time
date +%s > /tmp/task_start_time.txt

take_screenshot /tmp/task_initial.png
echo "=== Setup complete ==="