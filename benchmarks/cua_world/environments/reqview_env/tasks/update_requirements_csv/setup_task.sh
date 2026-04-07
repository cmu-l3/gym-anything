#!/bin/bash
set -e
echo "=== Setting up update_requirements_csv task ==="

source /workspace/scripts/task_utils.sh

# 1. Kill any running ReqView instances
pkill -f "reqview" 2>/dev/null || true
sleep 2

# 2. Setup a fresh project (copy from ExampleProject)
# We rename it to "Drone_Project" to match the scenario
PROJECT_DIR="/home/ga/Documents/ReqView/Drone_Project"
rm -rf "$PROJECT_DIR" 2>/dev/null || true
mkdir -p "$PROJECT_DIR"

# Use standard example project as base
if [ -d "/home/ga/Documents/ReqView/ExampleProject" ]; then
    cp -r "/home/ga/Documents/ReqView/ExampleProject/." "$PROJECT_DIR/"
elif [ -d "/workspace/data/ExampleProject" ]; then
    cp -r "/workspace/data/ExampleProject/." "$PROJECT_DIR/"
else
    echo "ERROR: Could not find base ExampleProject"
    exit 1
fi
chown -R ga:ga "$PROJECT_DIR"

# 3. Generate the CSV file dynamically based on the project's actual IDs
# We use Python to parse the SRS.json, pick some IDs, and create the CSV
SRS_JSON="$PROJECT_DIR/documents/SRS.json"
CSV_PATH="/home/ga/Documents/ReqView/Stakeholder_Review.csv"
GROUND_TRUTH_PATH="/home/ga/.hidden/ground_truth.json"
mkdir -p /home/ga/.hidden

python3 << PYEOF
import json
import csv
import random
import os

srs_path = "$SRS_JSON"
csv_path = "$CSV_PATH"
gt_path = "$GROUND_TRUTH_PATH"

try:
    with open(srs_path, 'r') as f:
        data = json.load(f)
except Exception as e:
    print(f"Error reading SRS.json: {e}")
    exit(1)

# Helper to recursively collect IDs
def get_ids(items, id_list):
    for item in items:
        # Only pick items that look like requirements (have an ID)
        if 'id' in item:
            id_list.append(item['id'])
        if 'children' in item:
            get_ids(item['children'], id_list)

all_ids = []
get_ids(data.get('data', []), all_ids)

# Filter for typical requirement IDs (usually integers in JSON, displayed as prefixes in UI)
# We accept any ID that is present.
candidate_ids = [x for x in all_ids if str(x).isdigit()]

if len(candidate_ids) < 5:
    print("Warning: Not enough IDs found, using whatever we have")
    
# Select 5-8 random IDs to update
sample_size = min(len(candidate_ids), random.randint(5, 8))
selected_ids = random.sample(candidate_ids, sample_size)

# Define choices
statuses = ["Accepted", "Rejected", "Draft"] # ReqView standard might vary, but "Accepted" usually maps if custom or text match
# Actually, the standard example project usually has Status: Draft, Changed, Review, Approved, Rejected.
# We will use "Approved" and "Rejected" as they are standard.
status_choices = ["Approved", "Rejected"]
priority_choices = ["High", "Medium", "Low"]

csv_data = []
ground_truth = {}

for rid in selected_ids:
    stat = random.choice(status_choices)
    prio = random.choice(priority_choices)
    
    # Prefix usually depends on document configuration, but for Import ID matching, 
    # ReqView often matches integer ID if column is mapped to 'ID'. 
    # However, to be safe for the user visual matching, we'll format as 'SRS-<id>'.
    # BUT, for the import to work 'Update by ID', providing just the integer is often safest 
    # if mapping to the internal ID field. 
    # Let's provide the displayed ID (e.g. SRS-12) if possible, but the internal ID logic 
    # in ReqView import is robust. Let's use the ID exactly as in the JSON (integers).
    
    csv_data.append({
        "Req_ID": str(rid),
        "Review_Decision": stat,
        "Urgency_Level": prio
    })
    
    ground_truth[str(rid)] = {
        "status": stat,
        "priority": prio
    }

# Write CSV
with open(csv_path, 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=["Req_ID", "Review_Decision", "Urgency_Level"])
    writer.writeheader()
    writer.writerows(csv_data)

# Write Ground Truth (hidden)
with open(gt_path, 'w') as f:
    json.dump(ground_truth, f, indent=2)

print(f"Generated CSV with {len(csv_data)} rows.")
PYEOF

chown ga:ga "$CSV_PATH"

# 4. Launch ReqView with the project
launch_reqview_with_project "$PROJECT_DIR"

# 5. Prepare UI
dismiss_dialogs
maximize_window
# Open SRS document explicitly to ensure agent sees it
open_srs_document

# 6. Record timestamp
date +%s > /tmp/task_start_time.txt
# Record initial SRS modification time
stat -c %Y "$SRS_JSON" > /tmp/srs_initial_mtime.txt

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="