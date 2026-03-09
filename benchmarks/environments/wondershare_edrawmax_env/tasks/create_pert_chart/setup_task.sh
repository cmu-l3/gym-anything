#!/bin/bash
echo "=== Setting up create_pert_chart task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Kill any existing EdrawMax instances to ensure clean state
echo "Killing any existing EdrawMax processes..."
kill_edrawmax

# Clean up previous output files
rm -f /home/ga/Diagrams/pert_migration.eddx 2>/dev/null || true
rm -f /home/ga/Diagrams/pert_migration.png 2>/dev/null || true
mkdir -p /home/ga/Diagrams

# Launch EdrawMax to Home Screen (no specific file loaded)
echo "Launching EdrawMax..."
launch_edrawmax

# Wait for EdrawMax to fully load
wait_for_edrawmax 90

# Dismiss startup dialogs (Account Login, File Recovery, Banner)
dismiss_edrawmax_dialogs

# Maximize the window
maximize_edrawmax

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="