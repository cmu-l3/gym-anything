#!/bin/bash
set -e
echo "=== Setting up find_untested_requirements task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure clean state
pkill -f "reqview" 2>/dev/null || true
sleep 2

# Remove any previous output file
rm -f /home/ga/Documents/untested_requirements.txt

# Setup a specific project copy for this task
PROJECT_PATH=$(setup_task_project "find_untested_reqs_project")
echo "Task project path: $PROJECT_PATH"

# Launch ReqView with the project
launch_reqview_with_project "$PROJECT_PATH"

# Dismiss dialogs and maximize
dismiss_dialogs
maximize_window

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="