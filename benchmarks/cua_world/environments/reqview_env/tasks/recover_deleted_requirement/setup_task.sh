#!/bin/bash
set -e
echo "=== Setting up recover_deleted_requirement task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Kill any running ReqView
pkill -f "reqview" 2>/dev/null || true
sleep 2

# 1. Setup Project
# We create a specific project instance for this task
PROJECT_PATH=$(setup_task_project "RecoverTask")
echo "Task project path: $PROJECT_PATH"

# 2. Perform the Deletion (The "Accident")
# We use UI automation to delete SRS-6 so the internal state is exactly what ReqView expects
# (i.e., properly moved to Deleted Objects repository).
echo "Launching ReqView to simulate data loss..."
launch_reqview_with_project "$PROJECT_PATH"

# Wait for window and maximize
wait_for_reqview 60
maximize_window

# Open SRS document
open_srs_document 5

echo "Deleting SRS-6..."
# 1. Open Find dialog
DISPLAY=:1 xdotool key ctrl+f
sleep 1
# 2. Type ID
DISPLAY=:1 xdotool type "SRS-6"
sleep 1
DISPLAY=:1 xdotool key Return
sleep 2
# 3. Close Find dialog (Esc)
DISPLAY=:1 xdotool key Escape
sleep 1
# 4. Delete the selected requirement
DISPLAY=:1 xdotool key Delete
sleep 1
# 5. Confirm deletion in popup (Enter)
DISPLAY=:1 xdotool key Return
sleep 2

# Save the "accident" state
DISPLAY=:1 xdotool key ctrl+s
sleep 2

# Close ReqView to ensure state is flushed to disk
pkill -f "reqview" 2>/dev/null || true
sleep 5

# 3. Prepare for Agent
# Relaunch the app so the agent starts with the app open
echo "Relaunching ReqView for agent..."
launch_reqview_with_project "$PROJECT_PATH"

wait_for_reqview 60
maximize_window
open_srs_document 3

# Take initial screenshot (Evidence: SRS-6 should be missing)
take_screenshot /tmp/task_initial.png
echo "Initial screenshot captured."

echo "=== Task setup complete ==="