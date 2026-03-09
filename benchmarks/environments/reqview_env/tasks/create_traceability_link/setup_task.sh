#!/bin/bash
echo "=== Setting up create_traceability_link task ==="

source /workspace/scripts/task_utils.sh

# Kill any running ReqView
pkill -f "reqview" 2>/dev/null || true
sleep 2

# Set up a fresh copy of the example project for this task
PROJECT_PATH=$(setup_task_project "traceability_link")
echo "Task project path: $PROJECT_PATH"

# Verify that SRS-245 and NEEDS-82 exist in the project data (required by the task).
# Both exist in the official ReqView example project — this check guards against
# accidental data corruption.
python3 << PYEOF
import json, sys

def find_id(items, target_id):
    for item in items:
        if item.get('id') == target_id:
            return item
        if 'children' in item:
            r = find_id(item['children'], target_id)
            if r: return r
    return None

srs_path = "$PROJECT_PATH/documents/SRS.json"
needs_path = "$PROJECT_PATH/documents/NEEDS.json"
ok = True
try:
    srs = json.load(open(srs_path))
    s245 = find_id(srs.get('data', []), '245')
    if not s245:
        print("ERROR: SRS-245 not found in SRS.json", file=sys.stderr)
        ok = False
    else:
        print(f"SRS-245 found: {str(s245.get('text',''))[:80]}")
except Exception as e:
    print(f"ERROR reading SRS.json: {e}", file=sys.stderr)
    ok = False

try:
    needs = json.load(open(needs_path))
    n82 = find_id(needs.get('data', []), '82')
    if not n82:
        print("ERROR: NEEDS-82 not found in NEEDS.json", file=sys.stderr)
        ok = False
    else:
        print(f"NEEDS-82 found (type={n82.get('type','')})")
except Exception as e:
    print(f"ERROR reading NEEDS.json: {e}", file=sys.stderr)
    ok = False

if ok:
    print("Data verification passed: SRS-245 and NEEDS-82 both exist")
else:
    print("WARNING: Data verification issues detected — task may not be completable")
PYEOF

# Launch ReqView with the project
launch_reqview_with_project "$PROJECT_PATH"

sleep 3

# Dismiss any dialogs
dismiss_dialogs

# Maximize window
maximize_window

# Open the SRS document so the agent can navigate to SRS-245 directly
# (The task step 1 says "Open the SRS document" — pre-opening it reduces
# unnecessary friction without removing meaningful task difficulty)
open_srs_document

take_screenshot /tmp/reqview_task_trace_link_start.png
echo "=== create_traceability_link task setup complete ==="
