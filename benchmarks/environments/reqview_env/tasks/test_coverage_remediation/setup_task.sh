#!/bin/bash
echo "=== Setting up test_coverage_remediation task ==="

source /workspace/scripts/task_utils.sh

# Kill any running ReqView
pkill -f "reqview" 2>/dev/null || true
sleep 2

# Set up a fresh copy of the example project for this task
PROJECT_PATH=$(setup_task_project "test_coverage")
echo "Task project path: $PROJECT_PATH"

# Record baseline count of items in TESTS document
python3 << 'PYEOF'
import json

tests_path = "$PROJECT_PATH/documents/TESTS.json"
with open(tests_path) as f:
    tests = json.load(f)

def count_items(items):
    total = 0
    for item in items:
        total += 1
        if 'children' in item:
            total += count_items(item['children'])
    return total

baseline = count_items(tests.get('data', []))
print(f"Baseline TESTS item count: {baseline}")

# Also count items with verification links
ver_count = 0
def count_ver(items):
    global ver_count
    for item in items:
        if item.get('links', {}).get('verification'):
            ver_count += 1
        if 'children' in item:
            count_ver(item['children'])
count_ver(tests.get('data', []))
print(f"Baseline items with verification links: {ver_count}")

# Verify the target SRS items exist
srs_path = "$PROJECT_PATH/documents/SRS.json"
with open(srs_path) as f:
    srs = json.load(f)

def find_id(items, tid):
    for item in items:
        if str(item.get('id')) == str(tid):
            return item
        if 'children' in item:
            r = find_id(item['children'], tid)
            if r: return r
    return None

for sid in ['61', '72', '76']:
    item = find_id(srs.get('data', []), sid)
    if item:
        print(f"SRS-{sid} found: {str(item.get('text',''))[:60]}")
    else:
        print(f"WARNING: SRS-{sid} not found!")

with open('/tmp/test_coverage_baseline_count', 'w') as f:
    f.write(str(baseline))
with open('/tmp/test_coverage_baseline_ver', 'w') as f:
    f.write(str(ver_count))
PYEOF

date +%s > /tmp/test_coverage_start_ts

# Launch ReqView with the project
launch_reqview_with_project "$PROJECT_PATH"

sleep 3

# Dismiss any dialogs
dismiss_dialogs

# Maximize window
maximize_window

# Open the TESTS document in the project tree
# TESTS is in L2: System group, below SRS
echo "Opening TESTS document from project tree..."
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool mousemove 114 435 click 1 2>/dev/null || true
sleep 4
echo "TESTS document opened"

take_screenshot /tmp/test_coverage_start.png
echo "=== test_coverage_remediation task setup complete ==="
