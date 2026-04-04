#!/bin/bash
set -e
echo "=== Setting up UML Use Case Diagram task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean up any previous task artifacts
rm -f /home/ga/Documents/PatientPortal_UseCaseDiagram.eddx
rm -f /tmp/task_initial_state.png
rm -f /tmp/task_final_state.png

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Kill any existing EdrawMax instances
kill_edrawmax

# Launch EdrawMax fresh (opens to home/template screen)
echo "Launching EdrawMax..."
launch_edrawmax

# Wait for EdrawMax to start
wait_for_edrawmax 90

# Dismiss any startup dialogs (login, file recovery, notifications)
dismiss_edrawmax_dialogs

# Maximize the window
maximize_edrawmax

# Wait for UI to fully settle
sleep 5

# Take screenshot of initial state
take_screenshot /tmp/task_initial_state.png

echo "=== UML Use Case Diagram task setup complete ==="