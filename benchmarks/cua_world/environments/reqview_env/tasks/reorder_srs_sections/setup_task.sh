#!/bin/bash
set -e
echo "=== Setting up reorder_srs_sections task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Kill any running ReqView
pkill -f "reqview" 2>/dev/null || true
sleep 2

# Set up fresh project copy
TASK_PROJECT=$(setup_task_project "reorder_srs_sections")
echo "Project created at: $TASK_PROJECT"

# Find the SRS JSON file and record baseline structure
# ReqView projects usually store docs in 'documents' folder
SRS_FILE=$(find "$TASK_PROJECT" -name "SRS.json" | head -1)

if [ -f "$SRS_FILE" ]; then
    echo "SRS file found: $SRS_FILE"
    echo "$SRS_FILE" > /tmp/srs_file_path.txt
    
    # Save baseline hash
    md5sum "$SRS_FILE" | awk '{print $1}' > /tmp/srs_baseline_hash.txt
    
    # Extract top-level section info for verification using Python
    # We save a simplified list of top-level IDs to verify the move later
    python3 << PYEOF
import json
import sys

srs_path = "$SRS_FILE"
output_path = "/tmp/baseline_structure.json"

try:
    with open(srs_path, 'r') as f:
        data = json.load(f)
    
    # ReqView document structure: 'data' is a list of top-level objects (sections/requirements)
    # Children are nested inside.
    # We only care about the top-level list for this task.
    top_level_items = data.get('data', [])
    
    baseline = []
    for idx, item in enumerate(top_level_items):
        # Extract ID and Heading/Text
        item_id = item.get('id', 'unknown')
        text = item.get('heading', item.get('text', ''))
        # Text might be html, crude strip
        text = str(text).replace('<p>', '').replace('</p>', '').strip()
        
        baseline.append({
            'index': idx,
            'id': item_id,
            'text': text[:50] # Truncate for log
        })
        
    with open(output_path, 'w') as f:
        json.dump(baseline, f, indent=2)
        
    print(f"Saved {len(baseline)} top-level items to baseline.")
    
except Exception as e:
    print(f"Error parsing SRS: {e}")
PYEOF

else
    echo "WARNING: SRS.json not found in project!"
fi

# Clean up any previous result file
rm -f /home/ga/reorder_result.txt

# Launch ReqView with the project
launch_reqview_with_project "$TASK_PROJECT"

sleep 5

# Dismiss any dialogs
dismiss_dialogs

# Maximize window
maximize_window

# Open the SRS document so it is visible
open_srs_document

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="