#!/bin/bash
set -e
echo "=== Setting up batch_assign_priorities task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Kill any running ReqView
pkill -f "reqview" 2>/dev/null || true
sleep 2

# Set up a fresh copy of the example project
PROJECT_PATH=$(setup_task_project "batch_priority")
echo "Task project path: $PROJECT_PATH"

# -----------------------------------------------------------------------------
# FAULT INJECTION: Clear priority of 5 random requirements in SRS.json
# -----------------------------------------------------------------------------
SRS_JSON="$PROJECT_PATH/documents/SRS.json"
TARGET_IDS_FILE="/tmp/target_req_ids.json"

python3 << PYEOF
import json
import random
import sys

srs_path = "$SRS_JSON"
target_file = "$TARGET_IDS_FILE"

try:
    with open(srs_path, 'r') as f:
        srs = json.load(f)
except Exception as e:
    print(f"Error reading SRS: {e}")
    sys.exit(1)

# Helper to collect leaf requirements (exclude headings/sections)
candidates = []

def collect_candidates(items):
    for item in items:
        # Check if it's a requirement (has text/description) and NOT a heading
        # In ReqView JSON, headings usually have a "heading" property
        if 'heading' not in item:
            # It's a requirement. It might have children, but we can still strip its priority.
            # We prefer items that already have a priority to strip, to ensure valid schema.
            if 'priority' in item:
                candidates.append(item)
        
        # Recurse
        if 'children' in item:
            collect_candidates(item['children'])

collect_candidates(srs.get('data', []))

if len(candidates) < 5:
    print(f"Warning: Only found {len(candidates)} candidates. Using all.")
    selection = candidates
else:
    selection = random.sample(candidates, 5)

target_ids = []
for item in selection:
    # Remove priority
    del item['priority']
    target_ids.append(item['id'])
    print(f"Cleared priority for Requirement ID: {item['id']}")

# Save modified SRS
with open(srs_path, 'w') as f:
    json.dump(srs, f, indent=2)

# Save target IDs for verification
with open(target_file, 'w') as f:
    json.dump(target_ids, f)

print(f"Setup complete. Modified {len(target_ids)} requirements.")
PYEOF

# -----------------------------------------------------------------------------
# LAUNCH REQVIEW
# -----------------------------------------------------------------------------

# Launch ReqView with the project
launch_reqview_with_project "$PROJECT_PATH"

# Wait for window
wait_for_reqview 60

# Dismiss dialogs
dismiss_dialogs

# Maximize window
maximize_window

# Open the SRS document explicitly
open_srs_document

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="