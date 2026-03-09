#!/bin/bash
echo "=== Setting up create_uml_timing_diagram task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure clean state: kill existing instances
echo "Killing any existing EdrawMax processes..."
kill_edrawmax

# Remove any previous task artifacts
rm -f /home/ga/Documents/entry_timing.eddx 2>/dev/null || true
rm -f /home/ga/Documents/entry_timing.png 2>/dev/null || true

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Launch EdrawMax (opens to Home/Template screen)
echo "Launching EdrawMax..."
launch_edrawmax

# Wait for EdrawMax to fully load
wait_for_edrawmax 90

# Dismiss startup dialogs (Account Login, File Recovery, Banners)
dismiss_edrawmax_dialogs

# Maximize the window
maximize_edrawmax

# Take a screenshot of initial state
take_screenshot /tmp/task_initial.png
echo "Initial screenshot saved to /tmp/task_initial.png"

echo "=== Task setup complete ==="