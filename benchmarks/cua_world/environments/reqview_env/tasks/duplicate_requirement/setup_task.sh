#!/bin/bash
set -e
echo "=== Setting up duplicate_requirement task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# Kill any existing ReqView instance
pkill -f "reqview" 2>/dev/null || true
sleep 2

# Set up a fresh copy of the example project
# This utility copies the template project to /home/ga/Documents/ReqView/duplicate_requirement_project
PROJECT_PATH=$(setup_task_project "duplicate_requirement")
echo "$PROJECT_PATH" > /tmp/task_project_path.txt
echo "Task project set up at: $PROJECT_PATH"

# Record initial requirement count
# We use a python script for accurate parsing of the JSON structure
SRS_FILE="$PROJECT_PATH/documents/SRS.json"

if [ -f "$SRS_FILE" ]; then
    INITIAL_COUNT=$(python3 -c "import json, sys; 
try:
    data = json.load(open('$SRS_FILE'))
    # Recursive count of items with 'id' (requirements/sections)
    def count_items(items):
        c = 0
        for i in items:
            c += 1
            if 'children' in i:
                c += count_items(i['children'])
        return c
    print(count_items(data.get('data', [])))
except Exception as e:
    print('0')
")
else
    echo "WARNING: SRS.json not found at $SRS_FILE"
    INITIAL_COUNT=0
fi

echo "$INITIAL_COUNT" > /tmp/initial_req_count.txt
echo "Initial requirement count: $INITIAL_COUNT"

# Launch ReqView with the task project
launch_reqview_with_project "$PROJECT_PATH"

# Maximize window
maximize_window

# Dismiss any startup dialogs
dismiss_dialogs

# Open the SRS document explicitly in the UI
open_srs_document 5

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== duplicate_requirement setup complete ==="