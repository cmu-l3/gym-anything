#!/bin/bash
echo "=== Setting up requirements_status_reconciliation task ==="

source /workspace/scripts/task_utils.sh

# Kill any running ReqView
pkill -f "reqview" 2>/dev/null || true
sleep 2

# Set up a fresh copy of the example project for this task
PROJECT_PATH=$(setup_task_project "status_reconciliation")
echo "Task project path: $PROJECT_PATH"

# Corrupt the status of 5 SRS requirements that are implemented by ARCH components.
# These requirements should have status "Released" but we change them to wrong values.
python3 << 'PYEOF'
import json, sys

srs_path = "$PROJECT_PATH/documents/SRS.json"

try:
    with open(srs_path) as f:
        srs = json.load(f)
except Exception as e:
    print(f"ERROR: Could not read SRS.json: {e}", file=sys.stderr)
    sys.exit(1)

# Status corruptions: SRS ID -> wrong status to set
corruptions = {
    "56":  "Draft",     # Open File — was Released
    "83":  "Reviewed",  # Requirements Table — was Released
    "106": "Draft",     # Create Requirement — was Released
    "137": "Ready",     # Traceability Links — was Released
    "163": "Reviewed",  # Print — was Released
}

def corrupt_status(items):
    count = 0
    for item in items:
        iid = str(item.get('id', ''))
        if iid in corruptions:
            old_status = item.get('status', '')
            new_status = corruptions[iid]
            item['status'] = new_status
            count += 1
            print(f"Corrupted SRS-{iid}: '{old_status}' -> '{new_status}'")
        if 'children' in item:
            count += corrupt_status(item['children'])
    return count

corrupted = corrupt_status(srs.get('data', []))
print(f"Total status corruptions: {corrupted}")

if corrupted != 5:
    print(f"WARNING: Expected 5 corruptions, got {corrupted}", file=sys.stderr)

with open(srs_path, 'w') as f:
    json.dump(srs, f, indent=2)
print("SRS status corruption complete")

# Verify ARCH implementation links exist for these requirements
arch_path = "$PROJECT_PATH/documents/ARCH.json"
try:
    with open(arch_path) as f:
        arch = json.load(f)
except Exception as e:
    print(f"WARNING: Could not read ARCH.json: {e}", file=sys.stderr)
    sys.exit(0)

# Collect all SRS IDs that ARCH implements
implemented_srs = set()
def collect_impl(items):
    for item in items:
        for target in item.get('links', {}).get('implementation', []):
            implemented_srs.add(target)
        if 'children' in item:
            collect_impl(item['children'])
collect_impl(arch.get('data', []))

for sid in corruptions:
    ref = f"SRS-{sid}"
    if ref in implemented_srs:
        print(f"Verified: {ref} is implemented by ARCH")
    else:
        print(f"WARNING: {ref} NOT found in ARCH implementation links!")
PYEOF

date +%s > /tmp/status_reconciliation_start_ts

# Launch ReqView with the project
launch_reqview_with_project "$PROJECT_PATH"

sleep 3

# Dismiss any dialogs
dismiss_dialogs

# Maximize window
maximize_window

# Open the SRS document
open_srs_document

take_screenshot /tmp/status_reconciliation_start.png
echo "=== requirements_status_reconciliation task setup complete ==="
