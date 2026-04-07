#!/bin/bash
set -e
echo "=== Setting up filter_requirements_report task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure clean state: kill any running ReqView instances
pkill -f "reqview" 2>/dev/null || true
sleep 2

# Set up a fresh copy of the example project for this task
# We use a unique project folder to avoid side effects from previous runs
PROJECT_PATH=$(setup_task_project "filter_report")
echo "Task project path: $PROJECT_PATH"

# Ensure the output directory exists
mkdir -p /home/ga/Documents/ReqView
# Remove any pre-existing report to prevent false positives
rm -f /home/ga/Documents/ReqView/monitoring_report.txt

# Launch ReqView with the project
# This uses the helper from task_utils.sh which handles nohup, display settings, etc.
launch_reqview_with_project "$PROJECT_PATH"

sleep 5

# Dismiss any startup dialogs (tips, trial notices, etc.)
dismiss_dialogs

# Maximize the window to ensure the UI (filter icons) is visible to the agent
maximize_window

# Open the SRS document specifically.
# The project tree is visible, but the document editor might be empty initially.
open_srs_document

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="