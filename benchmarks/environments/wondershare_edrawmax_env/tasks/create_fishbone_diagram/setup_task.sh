#!/bin/bash
set -e
echo "=== Setting up create_fishbone_diagram task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Clean up previous run artifacts
rm -f /home/ga/Diagrams/fishbone_outage_rca.eddx
rm -f /home/ga/Diagrams/fishbone_outage_rca.png
rm -f /tmp/task_result.json

# Ensure output directory exists
mkdir -p /home/ga/Diagrams
chown ga:ga /home/ga/Diagrams

# 3. Kill any existing EdrawMax instances to ensure clean state
echo "Killing existing EdrawMax processes..."
kill_edrawmax

# 4. Launch EdrawMax (Start at Home Screen / Template Gallery)
echo "Launching EdrawMax..."
launch_edrawmax

# 5. Wait for application to load
wait_for_edrawmax 90

# 6. Dismiss startup dialogs (Account Login, File Recovery, Banners)
dismiss_edrawmax_dialogs

# 7. Maximize window
maximize_edrawmax

# 8. Capture initial state screenshot
take_screenshot /tmp/task_initial.png
echo "Initial state screenshot captured."

echo "=== Task setup complete ==="