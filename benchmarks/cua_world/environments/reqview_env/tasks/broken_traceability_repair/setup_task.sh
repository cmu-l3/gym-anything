#!/bin/bash
echo "=== Setting up broken_traceability_repair task ==="

source /workspace/scripts/task_utils.sh

# Kill any running ReqView
pkill -f "reqview" 2>/dev/null || true
sleep 2

# Set up a fresh copy of the example project for this task
PROJECT_PATH=$(setup_task_project "broken_traceability")
echo "Task project path: $PROJECT_PATH"

# Corrupt 4 satisfaction links in the SRS document by changing their NEEDS targets
# to non-existent IDs. The agent must find these broken links and repair them.
python3 << 'PYEOF'
import json, sys

srs_path = "$PROJECT_PATH/documents/SRS.json"

try:
    with open(srs_path) as f:
        srs = json.load(f)
except Exception as e:
    print(f"ERROR: Could not read SRS.json: {e}", file=sys.stderr)
    sys.exit(1)

# Corruption targets: SRS ID -> (wrong NEEDS target, correct NEEDS target)
corruptions = {
    "72":  ("NEEDS-999", "NEEDS-27"),   # Import from Word
    "106": ("NEEDS-998", "NEEDS-17"),   # Create new requirement
    "132": ("NEEDS-997", "NEEDS-24"),   # Comment requirement
    "137": ("NEEDS-996", "NEEDS-21"),   # Create traceability links
}

def corrupt_links(items):
    count = 0
    for item in items:
        iid = str(item.get('id', ''))
        if iid in corruptions:
            links = item.get('links', {})
            sat = links.get('satisfaction', [])
            wrong_target, correct_target = corruptions[iid]
            # Replace the correct target with the wrong one
            if correct_target in sat:
                idx = sat.index(correct_target)
                sat[idx] = wrong_target
                item['links']['satisfaction'] = sat
                count += 1
                print(f"Corrupted SRS-{iid}: {correct_target} -> {wrong_target}")
            else:
                print(f"WARNING: SRS-{iid} does not have {correct_target} in satisfaction links")
                # Add the wrong target anyway
                sat.append(wrong_target)
                item['links']['satisfaction'] = sat
                count += 1
                print(f"Added wrong link to SRS-{iid}: {wrong_target}")
        if 'children' in item:
            count += corrupt_links(item['children'])
    return count

corrupted = corrupt_links(srs.get('data', []))
print(f"Total corrupted links: {corrupted}")

with open(srs_path, 'w') as f:
    json.dump(srs, f, indent=2)

print("SRS link corruption complete")
PYEOF

date +%s > /tmp/broken_traceability_start_ts

# Launch ReqView with the project
launch_reqview_with_project "$PROJECT_PATH"

sleep 3

# Dismiss any dialogs
dismiss_dialogs

# Maximize window
maximize_window

# Open the SRS document
open_srs_document

take_screenshot /tmp/broken_traceability_start.png
echo "=== broken_traceability_repair task setup complete ==="
