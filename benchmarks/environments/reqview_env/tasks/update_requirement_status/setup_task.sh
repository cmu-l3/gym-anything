#!/bin/bash
echo "=== Setting up update_requirement_status task ==="

source /workspace/scripts/task_utils.sh

# Kill any running ReqView
pkill -f "reqview" 2>/dev/null || true
sleep 2

# Set up a fresh copy of the example project for this task
PROJECT_PATH=$(setup_task_project "update_req_status")
echo "Task project path: $PROJECT_PATH"

# Inject the target requirement into the SRS document (Security > Secure Input section)
# so the agent can find it by searching for "minimum password length"
SRS_JSON="$PROJECT_PATH/documents/SRS.json"
if [ -f "$SRS_JSON" ]; then
    python3 << PYEOF
import json, uuid, sys

srs_path = "$SRS_JSON"
try:
    with open(srs_path) as f:
        srs = json.load(f)
except Exception as e:
    print(f"ERROR reading SRS.json: {e}", file=sys.stderr)
    sys.exit(0)  # Non-fatal: proceed without injection

def find_and_inject(items, target_id, new_item):
    for item in items:
        if item.get('id') == target_id:
            if 'children' not in item:
                item['children'] = []
            item['children'].append(new_item)
            return True
        if 'children' in item:
            if find_and_inject(item['children'], target_id, new_item):
                return True
    return False

new_req = {
    "id": "246",
    "guid": str(uuid.uuid4()),
    "text": "<p>The application shall enforce a minimum password length of 12 characters for all user accounts.</p>",
    "status": "Draft",
    "type": "NFR"
}

# Inject into Security > Secure Input section (id=224)
injected = find_and_inject(srs['data'], '224', new_req)
if injected:
    srs['lastId'] = 246
    with open(srs_path, 'w') as f:
        json.dump(srs, f, indent=2)
    print("Injected 'minimum password length' requirement as SRS-246 (status=Draft) into Security > Secure Input")
else:
    print("WARNING: Could not find section id=224 to inject requirement")
PYEOF
else
    echo "WARNING: SRS.json not found at $SRS_JSON — proceeding without injection"
fi

# Launch ReqView with the project
launch_reqview_with_project "$PROJECT_PATH"

sleep 3

# Dismiss any dialogs
dismiss_dialogs

# Maximize window
maximize_window

# Open the SRS document in the project tree so it is visible to the agent
open_srs_document

take_screenshot /tmp/reqview_task_update_status_start.png
echo "=== update_requirement_status task setup complete ==="
