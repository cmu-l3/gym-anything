#!/bin/bash
set -e
echo "=== Setting up sync_req_status_with_tests task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Kill any running ReqView
pkill -f "reqview" 2>/dev/null || true
sleep 2

# Set up a fresh copy of the example project
PROJECT_PATH=$(setup_task_project "sync_status")
echo "Task project path: $PROJECT_PATH"

# Prepare the data: Reset SRS statuses and configure TESTS statuses to ensure coverage
# We use a Python script to modify the JSON files directly before the app starts
python3 << PYEOF
import json
import os
import glob
import sys

project_path = "$PROJECT_PATH"

# Helper to find doc by prefix
def find_doc_file(prefix):
    for f in glob.glob(os.path.join(project_path, "documents", "*.json")):
        try:
            with open(f, 'r') as fd:
                data = json.load(fd)
                if data.get('prefix') == prefix:
                    return f, data
        except:
            pass
    return None, None

srs_file, srs_data = find_doc_file("SRS")
tests_file, tests_data = find_doc_file("TESTS")

if not srs_file or not tests_file:
    print("ERROR: Could not find SRS or TESTS documents")
    sys.exit(1)

# Map SRS ID -> List of Test Objects (that link to it)
# In ReqView, links are directed. We need to check both directions,
# but usually TESTS link TO SRS (upstream).
# Let's look for links in TESTS pointing to SRS.
linked_tests = {}  # Map SRS_ID -> list of test items

def map_links(items):
    for item in items:
        # Check links
        if 'links' in item:
            for link in item['links']:
                # We need to know if this link points to an SRS item.
                # In this simple setup, we assume srcId points to SRS if the link is in TESTS.
                # (Ideally we verify the docId of the target, but local IDs are unique enough here)
                target_id = link.get('srcId') # ReqView link target
                if target_id:
                    if target_id not in linked_tests:
                        linked_tests[target_id] = []
                    linked_tests[target_id].append(item)
        
        if 'children' in item:
            map_links(item['children'])

map_links(tests_data.get('data', []))

print(f"Found {len(linked_tests)} SRS items with test links.")

# STRATEGY:
# 1. Select some SRS items to be 'Approved' case (All tests Approved)
# 2. Select some SRS items to be 'Rejected' case (At least one Rejected)
# 3. Reset all SRS items to 'Draft'

# Helper to update item status
def update_status(item, status):
    item['status'] = status

# Helper to traverse and reset SRS
def reset_srs(items):
    for item in items:
        if 'status' in item:
            item['status'] = 'Draft'
        if 'children' in item:
            reset_srs(item['children'])

reset_srs(srs_data.get('data', []))

# Configure Scenarios
keys = list(linked_tests.keys())
count = len(keys)

# Split into scenarios
# First 1/3: Approved
# Second 1/3: Rejected
# Rest: Mixed/Draft (we'll set tests to Draft)

for i, srs_id in enumerate(keys):
    tests = linked_tests[srs_id]
    if not tests: continue
    
    if i < count / 3:
        # SCENARIO: APPROVED
        for t in tests:
            t['status'] = 'Approved'
    elif i < 2 * count / 3:
        # SCENARIO: REJECTED
        # Set first test to Rejected, others to Approved
        tests[0]['status'] = 'Rejected'
        for t in tests[1:]:
            t['status'] = 'Approved'
    else:
        # SCENARIO: DRAFT (Tests not run yet)
        for t in tests:
            t['status'] = 'Draft'

# Generate Ground Truth
ground_truth = {} # srs_id -> expected_status

def calculate_expected(srs_id):
    tests = linked_tests.get(srs_id, [])
    if not tests:
        return 'Draft'
    
    statuses = [t.get('status', 'Draft') for t in tests]
    
    if 'Rejected' in statuses:
        return 'Rejected'
    if all(s == 'Approved' for s in statuses) and len(statuses) > 0:
        return 'Approved'
    return 'Draft'

# Recalculate for ALL SRS items (even unlinked ones)
def build_ground_truth(items):
    for item in items:
        if 'id' in item:
            ground_truth[item['id']] = calculate_expected(item['id'])
        if 'children' in item:
            build_ground_truth(item['children'])

build_ground_truth(srs_data.get('data', []))

# Save files
with open(srs_file, 'w') as f:
    json.dump(srs_data, f, indent=2)
with open(tests_file, 'w') as f:
    json.dump(tests_data, f, indent=2)
with open("/tmp/ground_truth.json", 'w') as f:
    json.dump(ground_truth, f, indent=2)

print("Data preparation complete. Ground truth saved to /tmp/ground_truth.json")
PYEOF

# Launch ReqView with the project
launch_reqview_with_project "$PROJECT_PATH"

sleep 3
dismiss_dialogs
maximize_window

# Open SRS document
open_srs_document

take_screenshot /tmp/reqview_task_initial.png
echo "=== Setup complete ==="