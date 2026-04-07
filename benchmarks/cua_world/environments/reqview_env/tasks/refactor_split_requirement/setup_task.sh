#!/bin/bash
echo "=== Setting up refactor_split_requirement task ==="

source /workspace/scripts/task_utils.sh

# Kill any running ReqView
pkill -f "reqview" 2>/dev/null || true
sleep 2

# Set up a fresh copy of the example project
PROJECT_PATH=$(setup_task_project "refactor_split_req")
echo "Task project path: $PROJECT_PATH"

# Record task start time
date +%s > /tmp/task_start_time.txt

# Inject the composite requirement into SRS-6
SRS_JSON="$PROJECT_PATH/documents/SRS.json"

if [ -f "$SRS_JSON" ]; then
    python3 << PYEOF
import json, sys, os

srs_path = "$SRS_JSON"
composite_text = "The system shall encrypt all sensitive user data stored locally using AES-256 encryption, and it shall transmit all data to the backend server using TLS 1.3 or higher."

try:
    with open(srs_path, 'r') as f:
        doc = json.load(f)

    # Helper to find and update ID 6
    found = False
    def update_req(items):
        nonlocal found
        for item in items:
            # Check ID as string or int
            if str(item.get('id')) == "6":
                item['text'] = composite_text
                # Reset attributes to ensure it looks like a standard requirement
                item['heading'] = None # Ensure it's not a section heading
                found = True
                return True
            if 'children' in item:
                if update_req(item['children']):
                    return True
        return False
    
    # If ID 6 exists, update it. If not, we might need to inject it, 
    # but the example project usually has IDs 1..N. 
    # If 6 is missing, we will hijack the first leaf node requirement we find.
    if not update_req(doc.get('data', [])):
        print("SRS-6 not found, attempting to hijack the first leaf node...")
        def hijack_first(items):
            for item in items:
                if 'children' not in item or not item['children']:
                    # It's a leaf
                    item['id'] = "6" # Force ID to 6
                    item['text'] = composite_text
                    return True
                if 'children' in item:
                    if hijack_first(item['children']):
                        return True
            return False
        hijack_first(doc.get('data', []))

    with open(srs_path, 'w') as f:
        json.dump(doc, f, indent=2)
    print("Successfully injected composite requirement into SRS-6")

except Exception as e:
    print(f"Error injecting data: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
else
    echo "ERROR: SRS.json not found at $SRS_JSON"
    exit 1
fi

# Launch ReqView with the project
launch_reqview_with_project "$PROJECT_PATH"

sleep 5

# Dismiss dialogs
dismiss_dialogs

# Maximize window
maximize_window

# Open the SRS document explicitly so the agent sees the data immediately
open_srs_document

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="