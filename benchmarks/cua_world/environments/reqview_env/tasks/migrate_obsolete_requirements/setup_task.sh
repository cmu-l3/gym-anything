#!/bin/bash
set -e
echo "=== Setting up Migrate Obsolete Requirements task ==="

source /workspace/scripts/task_utils.sh

# Kill any running ReqView
pkill -f "reqview" 2>/dev/null || true
sleep 2

# 1. Setup Project
# Create a fresh project directory based on the example
PROJECT_DIR=$(setup_task_project "smart_thermostat")
DOCS_DIR="$PROJECT_DIR/documents"

echo "Project initialized at: $PROJECT_DIR"

# 2. Inject 'Obsolete' status into SRS requirements using Python
# We also record which IDs we marked as obsolete for the verifier
python3 << PYEOF
import json
import os
import glob
import sys

# Find SRS file
docs_dir = '$DOCS_DIR'
srs_file = None
# Try strictly named SRS.json first, then fallback
if os.path.exists(os.path.join(docs_dir, 'SRS.json')):
    srs_file = os.path.join(docs_dir, 'SRS.json')
else:
    for f in glob.glob(os.path.join(docs_dir, '*.json')):
        try:
            with open(f, 'r') as fp:
                data = json.load(fp)
                if data.get('name') == 'SRS' or data.get('prefix') == 'SRS':
                    srs_file = f
                    break
        except:
            continue

if not srs_file:
    print('Error: SRS document not found', file=sys.stderr)
    sys.exit(1)

print(f'Modifying {srs_file}...')
with open(srs_file, 'r') as f:
    doc = json.load(f)

obsolete_ids = []
active_ids = []

# Helper to traverse and modify
def process_items(items):
    count = 0
    for item in items:
        # Only process requirement objects (those with IDs)
        if 'id' in item:
            count += 1
            # Mark arbitrary indices as Obsolete (e.g., 2nd, 5th, 8th items)
            # using hash of ID to be deterministic but scattered
            item_id_suffix = item['id'].split('-')[-1] if '-' in item['id'] else item['id']
            try:
                numeric_id = int(item_id_suffix)
                # Mark roughly 20-25% as obsolete
                if numeric_id % 4 == 0: 
                    item['status'] = 'Obsolete'
                    # Add visual cue
                    current_text = item.get('text', '')
                    item['text'] = current_text + " <br><b>[DEPRECATED]</b>"
                    obsolete_ids.append(item['id'])
                else:
                    active_ids.append(item['id'])
            except ValueError:
                active_ids.append(item['id'])
        
        if 'children' in item:
            process_items(item['children'])

if 'data' in doc: # ReqView 2.x structure
    process_items(doc['data'])
elif 'children' in doc: # Legacy structure
    process_items(doc['children'])

# Save modified SRS
with open(srs_file, 'w') as f:
    json.dump(doc, f, indent=4)

# Save ground truth for verification
ground_truth = {
    "obsolete_ids": obsolete_ids,
    "active_ids": active_ids,
    "srs_filename": os.path.basename(srs_file),
    "project_dir": "$PROJECT_DIR"
}
with open('/tmp/expected_obsolete_ids.json', 'w') as f:
    json.dump(ground_truth, f, indent=2)

print(f"Marked {len(obsolete_ids)} items as Obsolete")
PYEOF

# 3. Launch ReqView
echo "Launching ReqView..."
launch_reqview_with_project "$PROJECT_DIR"

# 4. Record start time
date +%s > /tmp/task_start_time.txt

# 5. Open SRS document
open_srs_document 5

# 6. Take initial screenshot
take_screenshot "/tmp/task_initial.png"

echo "=== Setup complete ==="