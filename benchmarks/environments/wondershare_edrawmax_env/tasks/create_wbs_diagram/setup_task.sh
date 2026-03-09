#!/bin/bash
set -e
echo "=== Setting up WBS Diagram Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Clean any previous task artifacts
rm -f /home/ga/Diagrams/erp_migration_wbs.eddx 2>/dev/null || true
rm -f /home/ga/Diagrams/erp_migration_wbs.png 2>/dev/null || true

# Ensure output directory exists
mkdir -p /home/ga/Diagrams
chown ga:ga /home/ga/Diagrams

# Kill any existing EdrawMax instance
echo "Killing existing EdrawMax instances..."
kill_edrawmax

# Launch EdrawMax fresh (opens to Home/New screen)
echo "Launching EdrawMax..."
launch_edrawmax

# Wait for it to start
wait_for_edrawmax 90

# Give UI extra time to fully render
sleep 15

# Dismiss startup dialogs (Account Login, File Recovery, Banners)
dismiss_edrawmax_dialogs

# Maximize the window
maximize_edrawmax

# Take initial state screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== WBS Diagram Task setup complete ==="