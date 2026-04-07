#!/bin/bash
set -e
echo "=== Setting up add_requirement_comment task ==="

source /workspace/scripts/task_utils.sh

# 1. Kill any existing ReqView instances
pkill -f "reqview" 2>/dev/null || true
sleep 2

# 2. Setup a fresh project
# We use a unique project folder for this task to ensure a clean state
PROJECT_PATH=$(setup_task_project "add_comment")
echo "Task project created at: $PROJECT_PATH"

# 3. Snapshot initial state for anti-gaming verification
# We calculate checksums of all JSON files to detect changes later
mkdir -p /tmp/reqview_initial
find "$PROJECT_PATH" -name "*.json" -type f -exec md5sum {} \; | sort > /tmp/reqview_initial/checksums.txt
date +%s > /tmp/task_start_time.txt

# 4. Launch ReqView with the project
# This opens the project but usually does not open a specific document tab by default
launch_reqview_with_project "$PROJECT_PATH"

# 5. Prepare window state
dismiss_dialogs
maximize_window

# 6. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="