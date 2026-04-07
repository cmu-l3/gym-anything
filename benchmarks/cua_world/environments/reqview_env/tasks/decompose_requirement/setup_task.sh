#!/bin/bash
set -e
echo "=== Setting up decompose_requirement task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Kill any running ReqView instances
pkill -f "reqview" 2>/dev/null || true
sleep 2

# Set up a fresh copy of the example project
# We use a unique name 'decompose_req_project' to avoid conflicts
PROJECT_PATH=$(setup_task_project "decompose_req")
echo "Task project path: $PROJECT_PATH"

# Launch ReqView with the project
launch_reqview_with_project "$PROJECT_PATH"

sleep 3

# Dismiss any startup dialogs
dismiss_dialogs

# Maximize window
maximize_window

# Open the SRS document so it's ready for the agent
open_srs_document

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="