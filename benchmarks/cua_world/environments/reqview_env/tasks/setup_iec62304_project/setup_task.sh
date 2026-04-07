#!/bin/bash
echo "=== Setting up setup_iec62304_project task ==="

source /workspace/scripts/task_utils.sh

# Kill any running ReqView instances
pkill -f "reqview" 2>/dev/null || true
sleep 2

# Delete stale output files BEFORE recording timestamp
rm -f /home/ga/Documents/arch_test_coverage.json 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/task_initial.png 2>/dev/null || true
rm -f /tmp/task_final.png 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure the ExampleProject exists
PROJECT_PATH="/home/ga/Documents/ReqView/ExampleProject"
if [ ! -d "$PROJECT_PATH" ] || [ ! -f "$PROJECT_PATH/project.json" ]; then
    echo "ExampleProject not found, copying from workspace data..."
    mkdir -p "$PROJECT_PATH"
    cp -r /workspace/data/ExampleProject/. "$PROJECT_PATH/"
    chown -R ga:ga "$PROJECT_PATH"
fi

# Ensure output directory exists and is writable
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Launch ReqView with the ExampleProject
launch_reqview_with_project "$PROJECT_PATH"

sleep 5

# Dismiss any startup dialogs
dismiss_dialogs

# Maximize window
maximize_window

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== setup_iec62304_project setup complete ==="
