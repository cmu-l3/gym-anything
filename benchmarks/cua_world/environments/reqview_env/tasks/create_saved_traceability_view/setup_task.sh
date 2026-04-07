#!/bin/bash
set -e
echo "=== Setting up create_saved_traceability_view task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Kill any running ReqView instances
pkill -f "reqview" 2>/dev/null || true
sleep 2

# Set up a fresh copy of the example project
# We use a specific project folder for this task to avoid pollution
PROJECT_PATH=$(setup_task_project "rtm_view_task")
echo "Task project path: $PROJECT_PATH"

# Launch ReqView with the project
# This uses the utility function to handle nohup, display, and waiting
launch_reqview_with_project "$PROJECT_PATH"

# Give the app a moment to settle
sleep 5

# Dismiss any startup dialogs (EULA, welcome, etc.)
dismiss_dialogs

# Maximize the window for better agent visibility
maximize_window

# Explicitly open the SRS document so the agent starts in the right context
# (Navigating to the document is part of the task, but starting with it visible 
# reduces friction for the 'Open SRS' step)
open_srs_document

# Capture initial screenshot for evidence
take_screenshot /tmp/task_initial.png
echo "Initial screenshot captured"

echo "=== Task setup complete ==="