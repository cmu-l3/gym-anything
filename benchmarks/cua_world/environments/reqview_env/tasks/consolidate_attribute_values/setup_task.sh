#!/bin/bash
echo "=== Setting up consolidate_attribute_values task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Kill any running ReqView
pkill -f "reqview" 2>/dev/null || true
sleep 2

# Set up a fresh copy of the example project
PROJECT_DIR="/home/ga/Documents/ReqView/messy_project"
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR"

# Copy base example project
if [ -d "/home/ga/Documents/ReqView/ExampleProject" ]; then
    cp -r "/home/ga/Documents/ReqView/ExampleProject/." "$PROJECT_DIR/"
else
    # Fallback if example project missing (shouldn't happen in this env)
    mkdir -p "$PROJECT_DIR/documents"
    echo '{"id":"messy","name":"Messy Project"}' > "$PROJECT_DIR/project.json"
fi

chown -R ga:ga "$PROJECT_DIR"

# INJECT MESSY DATA
# We use Python to modify project.json (add attribute def) and SRS.json (assign bad values)
python3 << 'PYEOF'
import json
import os
import random
import sys

project_dir = "/home/ga/Documents/ReqView/messy_project"
project_json_path = os.path.join(project_dir, "project.json")
srs_json_path = os.path.join(project_dir, "documents/SRS.json")

ATTR_ID = "team_attr"
MESSY_VALUES = [
    "Hardware", "HW", "H/W", "Hard-ware",
    "Software", "SW", "S/W", "Soft",
    "Systems"
]

# 1. Update project.json to include the Team attribute definition
try:
    with open(project_json_path, 'r') as f:
        proj = json.load(f)
    
    # Ensure attributes list exists
    if "attributes" not in proj:
        proj["attributes"] = []
    elif isinstance(proj["attributes"], dict):
        # Convert dict to list if necessary (ReqView sometimes uses dicts keyed by ID)
        proj["attributes"] = list(proj["attributes"].values())

    # Check if attribute already exists (unlikely in fresh copy)
    existing = next((a for a in proj["attributes"] if a.get("id") == ATTR_ID), None)
    if not existing:
        new_attr = {
            "id": ATTR_ID,
            "name": "Team",
            "type": "enum",
            "values": MESSY_VALUES,
            "default": ""
        }
        proj["attributes"].append(new_attr)
    
    with open(project_json_path, 'w') as f:
        json.dump(proj, f, indent=2)
    print("Updated project.json with Team attribute")

except Exception as e:
    print(f"Error updating project.json: {e}")
    sys.exit(1)

# 2. Update SRS.json to assign messy values to requirements
try:
    with open(srs_json_path, 'r') as f:
        srs = json.load(f)

    def get_leaves(items):
        leaves = []
        for item in items:
            if 'children' in item and item['children']:
                leaves.extend(get_leaves(item['children']))
            else:
                leaves.append(item)
        return leaves

    leaves = get_leaves(srs.get("data", []))
    
    # Deterministic "randomness" for reproducibility
    rng = random.Random(42)
    
    # Allocation stats
    counts = {v: 0 for v in MESSY_VALUES}
    
    # We want roughly:
    # 10 Hardware variations
    # 10 Software variations
    # 5 Systems
    # Rest None
    
    targets = leaves[:25] # Take first 25 requirements
    
    hw_vars = ["Hardware", "HW", "H/W", "Hard-ware"]
    sw_vars = ["Software", "SW", "S/W", "Soft"]
    
    for i, item in enumerate(targets):
        val = None
        if i < 10:
            val = rng.choice(hw_vars)
        elif i < 20:
            val = rng.choice(sw_vars)
        elif i < 25:
            val = "Systems"
        
        if val:
            item[ATTR_ID] = val
            counts[val] += 1

    # Save initial counts to a file for the verifier to use as ground truth
    with open("/tmp/initial_counts.json", "w") as f:
        json.dump(counts, f)

    with open(srs_json_path, 'w') as f:
        json.dump(srs, f, indent=2)
    print(f"Updated SRS.json with messy values: {counts}")

except Exception as e:
    print(f"Error updating SRS.json: {e}")
    sys.exit(1)
PYEOF

# Launch ReqView with the project
echo "Launching ReqView..."
launch_reqview_with_project "$PROJECT_DIR"

sleep 5

# Dismiss dialogs
dismiss_dialogs
maximize_window

# Ensure the columns are visible might be tricky programmatically, 
# but the agent should be able to configure the view or use the dialogs.
# We just open the SRS document.
open_srs_document

# Take screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="