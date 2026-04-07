#!/bin/bash
set -e
echo "=== Setting up configure_table_columns task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# Kill any existing ReqView instance
pkill -f "reqview" 2>/dev/null || true
sleep 2

# Set up a fresh copy of the example project
PROJECT_PATH=$(setup_task_project "configure_columns")
echo "Task project path: $PROJECT_PATH"

# Launch ReqView with the project
# This uses the utility function which handles nohup, display, etc.
launch_reqview_with_project "$PROJECT_PATH"

# Wait for window to settle
sleep 5

# Dismiss any startup dialogs (e.g. "What's New")
dismiss_dialogs

# Maximize the window for clear visibility
maximize_window

# Open the SRS document explicitly so the agent starts in the right context
open_srs_document

# Capture initial screenshot (evidence of starting state)
echo "Capturing initial state..."
take_screenshot /tmp/task_initial.png

# Verify initial screenshot capture
if [ -f /tmp/task_initial.png ]; then
    echo "Initial screenshot captured successfully"
else
    echo "WARNING: Failed to capture initial screenshot"
fi

echo "=== Task setup complete ==="