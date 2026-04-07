#!/bin/bash
set -e
echo "=== Setting up Deprecate Legacy Requirements Task ==="

# Source utility functions
source /workspace/scripts/task_utils.sh

# 1. Record Start Time
date +%s > /tmp/task_start_time.txt

# 2. Prepare Project
# Kill any running ReqView
pkill -f "reqview" 2>/dev/null || true
sleep 2

# Create a fresh task project from the example base
TASK_PROJECT_DIR=$(setup_task_project "deprecate_legacy_requirements")
echo "Project directory: $TASK_PROJECT_DIR"
SRS_JSON="$TASK_PROJECT_DIR/documents/SRS.json"

# 3. Inject 'T-800' Scenarios and Generate Ground Truth
# We modify the SRS document to contain "T-800" in random requirements.
# We also ensure those requirements are NOT already 'Low' priority.

python3 << PYEOF
import json
import random
import sys
import os

srs_path = "$SRS_JSON"
ground_truth_path = "/tmp/legacy_targets.json"

if not os.path.exists(srs_path):
    print(f"ERROR: SRS file not found at {srs_path}")
    sys.exit(1)

try:
    with open(srs_path, 'r') as f:
        doc_data = json.load(f)
except Exception as e:
    print(f"ERROR: Failed to load SRS json: {e}")
    sys.exit(1)

# Helper to flatten the hierarchy and get modifiable requirement objects
def get_requirements(node, list_out):
    # A node is a requirement if it has an ID
    if isinstance(node, dict):
        if 'id' in node:
            list_out.append(node)
        
        if 'children' in node and isinstance(node['children'], list):
            for child in node['children']:
                get_requirements(child, list_out)
    elif isinstance(node, list):
        for item in node:
            get_requirements(item, list_out)

all_reqs = []
# Handle both root list or root dict with 'data'/'children'
if isinstance(doc_data, list):
    get_requirements(doc_data, all_reqs)
elif isinstance(doc_data, dict):
    root_data = doc_data.get('data', doc_data.get('children', []))
    get_requirements(root_data, all_reqs)

print(f"Found {len(all_reqs)} requirements total.")

if len(all_reqs) < 10:
    print("WARNING: Project has too few requirements to inject properly.")
    # Proceed anyway, but might be less effective

# Select 4-6 random targets, skipping the first few (often headers/intro)
targets = random.sample(all_reqs[2:], k=min(len(all_reqs)-2, 5))
target_ids = []

for req in targets:
    # 1. Inject "T-800" into text
    # ReqView text is often HTML. We append to the end inside the tag if possible, or just append.
    original_text = req.get('text', '')
    if '</' in original_text:
        # crude insertion before last tag
        parts = original_text.rsplit('<', 1)
        req['text'] = parts[0] + " (Legacy T-800 specification).<" + parts[1]
    else:
        req['text'] = original_text + " (Legacy T-800 specification)."
    
    # 2. Reset attributes to ensure they aren't already correct
    # Ensure Priority is NOT Low (set to High)
    # ReqView stores enum keys usually (H, M, L). We set to 'High'.
    req['priority'] = 'High'
    
    # Ensure description doesn't already start with DEPRECATED
    # (Already handled by just appending to text above)
    
    target_ids.append(req.get('id'))

print(f"Injected T-800 into IDs: {target_ids}")

# Save Ground Truth
with open(ground_truth_path, 'w') as gt:
    json.dump(target_ids, gt)

# Save Modified SRS
with open(srs_path, 'w') as f:
    json.dump(doc_data, f, indent=2)

PYEOF

# 4. Launch ReqView
echo "Launching ReqView..."
launch_reqview_with_project "$TASK_PROJECT_DIR"

# 5. Open SRS Document explicitly
open_srs_document

# 6. Capture State
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="