#!/bin/bash
echo "=== Setting up add_requirement task ==="

source /workspace/scripts/task_utils.sh

# Kill any running ReqView
pkill -f "reqview" 2>/dev/null || true
sleep 2

# Set up a fresh copy of the example project for this task
PROJECT_PATH=$(setup_task_project "add_requirement")
echo "Task project path: $PROJECT_PATH"

# Launch ReqView with the project
launch_reqview_with_project "$PROJECT_PATH"

sleep 3

# Dismiss any dialogs (trial notice, what's new, etc.)
dismiss_dialogs

# Maximize window for best agent view
maximize_window

# Open the SRS document in the project tree so it is visible to the agent
open_srs_document

take_screenshot /tmp/reqview_task_add_req_start.png
echo "=== add_requirement task setup complete ==="
