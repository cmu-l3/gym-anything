#!/bin/bash
set -e
echo "=== Setting up create_event_location_map task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Clean up previous artifacts
rm -f /home/ga/Documents/event_map.eddx
rm -f /home/ga/Documents/event_map.png
rm -f /tmp/task_result.json

# 3. Ensure EdrawMax is not running
kill_edrawmax

# 4. Launch EdrawMax to Home Screen (no specific file loaded)
echo "Launching EdrawMax..."
launch_edrawmax

# 5. Wait for application window
wait_for_edrawmax 90

# 6. Dismiss any startup dialogs (Login, Recovery, Banners)
dismiss_edrawmax_dialogs

# 7. Maximize window for agent visibility
maximize_edrawmax

# 8. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="