#!/bin/bash
echo "=== Setting up asvs_contamination_cleanup task ==="

source /workspace/scripts/task_utils.sh

# Kill any running ReqView
pkill -f "reqview" 2>/dev/null || true
sleep 2

# Set up a fresh copy of the example project for this task
PROJECT_PATH=$(setup_task_project "asvs_contamination")
echo "Task project path: $PROJECT_PATH"

# Inject 4 non-security functional requirements from the SRS into the ASVS document.
# These are REAL requirements from the SRS document — they clearly do not belong
# in the OWASP ASVS (security verification standards) document.
# The agent must use domain knowledge to identify them as non-security items.
python3 << 'PYEOF'
import json, sys

asvs_path = "$PROJECT_PATH/documents/ASVS.json"
srs_path = "$PROJECT_PATH/documents/SRS.json"

try:
    with open(asvs_path) as f:
        asvs = json.load(f)
    with open(srs_path) as f:
        srs = json.load(f)
except Exception as e:
    print(f"ERROR: Could not read project files: {e}", file=sys.stderr)
    sys.exit(1)

# Record the count of legitimate items before injection
def count_items(items):
    total = 0
    for item in items:
        total += 1
        if 'children' in item:
            total += count_items(item['children'])
    return total

legitimate_count = count_items(asvs.get('data', []))
print(f"ASVS legitimate item count before injection: {legitimate_count}")

# Find specific SRS items to inject (by ID)
def find_by_id(items, target_id):
    for item in items:
        if str(item.get('id')) == str(target_id):
            return item
        if 'children' in item:
            r = find_by_id(item['children'], target_id)
            if r:
                return r
    return None

# IDs of SRS items to inject — these are real functional requirements that
# clearly do NOT belong in an OWASP security verification standard document
inject_specs = [
    ("53", "900"),   # "create a new empty document" — file operation
    ("77", "901"),   # "export requirements to CSV" — export feature
    ("109", "902"),  # "move selected requirements" — document editing
    ("163", "903"),  # "print the displayed requirements table" — reporting
]

injected = []
for srs_id, new_id in inject_specs:
    item = find_by_id(srs.get('data', []), srs_id)
    if item:
        # Create a copy with a new ID (to avoid ID collision with existing ASVS items)
        injected_item = {
            "id": new_id,
            "guid": f"injected-{new_id}-from-srs-{srs_id}",
            "text": item.get("text", ""),
            "type": "INFO"  # Use ASVS-compatible type
        }
        injected.append(injected_item)
        print(f"Prepared injection: ASVS-{new_id} (from SRS-{srs_id})")
    else:
        print(f"WARNING: SRS-{srs_id} not found", file=sys.stderr)

if len(injected) != 4:
    print(f"ERROR: Expected 4 items to inject, got {len(injected)}", file=sys.stderr)
    sys.exit(1)

# Insert the contaminating items into different sections of ASVS to make
# them harder to spot — scatter them among legitimate content
data = asvs['data']

# Insert items into the children of sections at different depths
# Section structure: Introduction / V1: Architecture... / V2: Authentication...
def insert_at_depth(items, target_item, depth_target, current_depth=0):
    """Insert an item as a child of the first section found at depth_target."""
    for item in items:
        if current_depth == depth_target and 'children' in item:
            item['children'].append(target_item)
            return True
        if 'children' in item:
            if insert_at_depth(item['children'], target_item, depth_target, current_depth + 1):
                return True
    return False

# Place injected items in different sections
# Item 0: near the top level (among introductory sections)
if len(data) > 1 and 'children' in data[1]:
    data[1]['children'].append(injected[0])
    print(f"Injected ASVS-{injected[0]['id']} into Introduction section")

# Item 1: in a deeper section
inserted = insert_at_depth(data, injected[1], 2)
if not inserted:
    data.append(injected[1])
print(f"Injected ASVS-{injected[1]['id']} at depth 2")

# Item 2: in another section
inserted = insert_at_depth(data, injected[2], 3)
if not inserted:
    data.append(injected[2])
print(f"Injected ASVS-{injected[2]['id']} at depth 3")

# Item 3: near the end of the document
data.append(injected[3])
print(f"Injected ASVS-{injected[3]['id']} at end of document")

# Update the lastId to accommodate new items
asvs['lastId'] = max(int(asvs.get('lastId', 0)), 903)

with open(asvs_path, 'w') as f:
    json.dump(asvs, f, indent=2)

print(f"Injection complete: {len(injected)} items injected into ASVS")
PYEOF

# Record baseline: count of items in ASVS after injection
python3 -c "
import json
with open('$PROJECT_PATH/documents/ASVS.json') as f:
    asvs = json.load(f)
def count(items):
    t = 0
    for i in items:
        t += 1
        if 'children' in i:
            t += count(i['children'])
    return t
c = count(asvs.get('data', []))
print(c)
" > /tmp/asvs_contamination_initial_count

date +%s > /tmp/asvs_contamination_start_ts

# Launch ReqView with the project
launch_reqview_with_project "$PROJECT_PATH"

sleep 3

# Dismiss any dialogs
dismiss_dialogs

# Maximize window
maximize_window

# Open the ASVS document in the project tree
# ASVS is in L1: Stakeholders group, below NEEDS
# At approximately x=114, y=340 on a 1920x1080 display
echo "Opening ASVS document from project tree..."
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool mousemove 114 355 click 1 2>/dev/null || true
sleep 4
echo "ASVS document opened"

take_screenshot /tmp/asvs_contamination_start.png
echo "=== asvs_contamination_cleanup task setup complete ==="
