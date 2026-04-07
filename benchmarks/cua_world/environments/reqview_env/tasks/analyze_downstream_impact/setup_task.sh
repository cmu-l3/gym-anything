#!/bin/bash
echo "=== Setting up analyze_downstream_impact task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Kill any running ReqView instances
pkill -f "reqview" 2>/dev/null || true
sleep 2

# Clean up previous report if exists
rm -f /home/ga/Documents/ReqView/impact_report.json 2>/dev/null || true

# Set up a fresh copy of the example project
# We use a specific name so we can locate the modified files later
PROJECT_PATH=$(setup_task_project "impact_analysis")
echo "Task project path: $PROJECT_PATH"

# Save project path for export script
echo "$PROJECT_PATH" > /tmp/current_project_path.txt

# Launch ReqView with the project
launch_reqview_with_project "$PROJECT_PATH"

sleep 5

# Dismiss dialogs
dismiss_dialogs

# Maximize window
maximize_window

# Open SRS document to save the agent one click and ensure consistent starting state
open_srs_document

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="