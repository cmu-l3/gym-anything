#!/bin/bash
set -e
echo "=== Setting up remove_traceability_link task ==="

source /workspace/scripts/task_utils.sh

# 1. Kill any running ReqView instances
pkill -f "reqview" 2>/dev/null || true
sleep 2

# 2. Setup a fresh project directory
PROJECT_PATH=$(setup_task_project "remove_link_task")
echo "Task project path: $PROJECT_PATH"

# 3. Create hidden directory for verification data
mkdir -p /var/lib/reqview
chmod 777 /var/lib/reqview

# 4. Inject the incorrect link using Python
# We also save the 'valid' links to a baseline file for the verifier to check preservation.
SRS_JSON="$PROJECT_PATH/documents/SRS.json"
BASELINE_FILE="/var/lib/reqview/valid_links_baseline.json"

if [ -f "$SRS_JSON" ]; then
    python3 << PYEOF
import json
import sys
import os

srs_path = "$SRS_JSON"
baseline_path = "$BASELINE_FILE"
target_text_query = "session timeout"
bad_link = {"docId": "NEEDS", "reqId": "5", "type": "satisfies"}

try:
    with open(srs_path, 'r') as f:
        srs = json.load(f)
except Exception as e:
    print(f"ERROR: Could not read SRS.json: {e}", file=sys.stderr)
    sys.exit(1)

def find_req_by_text(items, text):
    for item in items:
        # Check text and description fields
        content = (item.get('text', '') + item.get('description', '')).lower()
        if text.lower() in content:
            return item
        if 'children' in item:
            res = find_req_by_text(item['children'], text)
            if res:
                return res
    return None

# Find the target requirement (SRS-4.3)
target_req = find_req_by_text(srs.get('data', []), target_text_query)

if not target_req:
    print(f"ERROR: Could not find requirement containing '{target_text_query}'", file=sys.stderr)
    # Fallback: try to find by ID if text fails (assuming example project structure)
    # In standard example, SRS-4.3 might correspond to an internal integer ID.
    # We proceed without failing to avoid crashing setup, but verify step will fail.
    sys.exit(0)

print(f"Found target requirement: ID={target_req.get('id')} Text={target_req.get('text','')[:30]}...")

# Save currently valid links to baseline (BEFORE injection)
valid_links = target_req.get('links', [])
with open(baseline_path, 'w') as f:
    json.dump({
        "req_id": target_req.get('id'),
        "valid_links": valid_links
    }, f)
print(f"Saved {len(valid_links)} valid links to baseline.")

# Inject the bad link
# Check if it already exists to avoid duplication
link_exists = False
for link in valid_links:
    if link.get('docId') == bad_link['docId'] and str(link.get('reqId')) == str(bad_link['reqId']):
        link_exists = True
        break

if not link_exists:
    if 'links' not in target_req:
        target_req['links'] = []
    target_req['links'].append(bad_link)
    
    # Save modified SRS
    with open(srs_path, 'w') as f:
        json.dump(srs, f, indent=2)
    print("Injected incorrect link to NEEDS-5")
else:
    print("Link to NEEDS-5 already exists")

PYEOF
else
    echo "ERROR: SRS.json not found at $SRS_JSON"
    exit 1
fi

# 5. Launch ReqView
echo "Launching ReqView..."
launch_reqview_with_project "$PROJECT_PATH"

# 6. Prepare UI state
sleep 5
dismiss_dialogs
maximize_window
open_srs_document

# 7. Record start time for file modification check
date +%s > /tmp/task_start_time.txt

# 8. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="