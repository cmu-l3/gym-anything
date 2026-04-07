#!/bin/bash
set -e
echo "=== Setting up document_math_formula task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Kill any running ReqView instances
pkill -f "reqview" 2>/dev/null || true
sleep 2

# Set up a fresh copy of the example project
# We use a unique name to ensure no collision with other tasks
PROJECT_PATH=$(setup_task_project "math_formula_project")
echo "Task project path: $PROJECT_PATH"

# Launch ReqView with the project
launch_reqview_with_project "$PROJECT_PATH"

# Wait for UI to settle
sleep 5

# Dismiss any startup dialogs (e.g. trial expiry, newsletter)
dismiss_dialogs

# Maximize window for consistent agent view
maximize_window

# Open the SRS document in the project tree so it is visible to the agent immediately
# This puts the agent in the correct context to start the task
open_srs_document

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="