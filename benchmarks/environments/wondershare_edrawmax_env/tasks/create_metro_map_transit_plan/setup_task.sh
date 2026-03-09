#!/bin/bash
echo "=== Setting up create_metro_map_transit_plan task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Clean up any previous artifacts
rm -f /home/ga/Documents/boston_metro_map.eddx
rm -f /home/ga/Documents/boston_metro_map.png

# Kill any running EdrawMax instances to ensure clean start
kill_edrawmax

# Launch EdrawMax (opens to Home/New screen)
echo "Launching EdrawMax..."
launch_edrawmax

# Wait for EdrawMax to fully load
wait_for_edrawmax 90

# Dismiss startup dialogs (Account Login, File Recovery, Banners)
dismiss_edrawmax_dialogs

# Maximize the window for visibility
maximize_edrawmax

# Navigate to Maps category if possible, or just leave at Home for agent to find
# Leaving at Home screen is better to test agent's ability to find "Metro Map"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="