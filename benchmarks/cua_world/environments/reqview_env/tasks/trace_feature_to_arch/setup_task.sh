#!/bin/bash
echo "=== Setting up trace_feature_to_arch task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Kill any running ReqView instances
pkill -f "reqview" 2>/dev/null || true
sleep 2

# Set up a fresh copy of the example project for this task
# Using a specific project name to isolate changes
PROJECT_PATH=$(setup_task_project "trace_feature")
echo "Task project path: $PROJECT_PATH"

# Record the project path for the verifier (though strictly the verifier can infer it)
echo "$PROJECT_PATH" > /tmp/task_project_path.txt

# Launch ReqView with the project
launch_reqview_with_project "$PROJECT_PATH"

sleep 5

# Dismiss any dialogs (trial notice, etc.)
dismiss_dialogs

# Maximize window for best agent view
maximize_window

# Ensure the project tree is visible but start with no document open
# (Agent must choose to open ARCH and SRS as needed)
# Just focusing the main window is sufficient.

# Take screenshot of initial state
take_screenshot /tmp/task_initial.png

echo "=== trace_feature_to_arch task setup complete ==="