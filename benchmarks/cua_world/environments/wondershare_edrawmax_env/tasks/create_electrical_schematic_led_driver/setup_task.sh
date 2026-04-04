#!/bin/bash
set -e
echo "=== Setting up Electrical Schematic Task ==="

source /workspace/scripts/task_utils.sh

# 1. Clean up previous run artifacts
rm -f /home/ga/Diagrams/led_driver_schematic.eddx 2>/dev/null || true
rm -f /home/ga/Diagrams/led_driver_schematic.png 2>/dev/null || true
mkdir -p /home/ga/Diagrams

# 2. Record start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 3. Ensure EdrawMax is running (Clean start)
echo "Killing any existing EdrawMax instances..."
kill_edrawmax

echo "Launching EdrawMax..."
# Launch without a file argument to land on the "New" / Home screen
# The agent must navigate to Engineering > Electrical themselves
launch_edrawmax

# 4. Wait for application to load
wait_for_edrawmax 90

# 5. Dismiss startup dialogs (Login, Recovery, etc.)
dismiss_edrawmax_dialogs

# 6. Maximize window
maximize_edrawmax

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="