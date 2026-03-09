#!/bin/bash
echo "=== Setting up create_venn_diagram task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Kill any existing EdrawMax processes to ensure a clean start
echo "Killing any existing EdrawMax processes..."
kill_edrawmax

# Remove output file if it exists from a previous run
rm -f /home/ga/Documents/cloud_services_venn.eddx 2>/dev/null || true

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Launch EdrawMax (opens to Home/New screen)
echo "Launching EdrawMax..."
launch_edrawmax

# Wait for EdrawMax to fully load
wait_for_edrawmax 90

# Dismiss startup dialogs (Account Login, File Recovery, Banners)
dismiss_edrawmax_dialogs

# Maximize the window to ensure agent has full visibility
maximize_edrawmax

# Take a screenshot to verify start state
take_screenshot /tmp/task_initial.png
echo "Start state screenshot saved to /tmp/task_initial.png"

echo "=== Task setup complete ==="
echo "EdrawMax is open. Agent should create a Venn diagram and save to /home/ga/Documents/cloud_services_venn.eddx"