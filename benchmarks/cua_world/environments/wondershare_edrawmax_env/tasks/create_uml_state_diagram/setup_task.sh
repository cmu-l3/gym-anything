#!/bin/bash
set -e
echo "=== Setting up create_uml_state_diagram task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
mkdir -p /home/ga/Diagrams
chown ga:ga /home/ga/Diagrams

# Clean up any previous task artifacts
rm -f /home/ga/Diagrams/order_state_machine.eddx 2>/dev/null || true
rm -f /home/ga/Diagrams/order_state_machine.png 2>/dev/null || true

# Kill any existing EdrawMax instances to start fresh
echo "Killing any existing EdrawMax processes..."
kill_edrawmax

# Launch EdrawMax (opens to Home/New screen)
echo "Launching EdrawMax..."
launch_edrawmax

# Wait for EdrawMax to fully load
wait_for_edrawmax 90

# Dismiss startup dialogs (Account Login, File Recovery, etc.)
dismiss_edrawmax_dialogs

# Maximize the window for visibility
maximize_edrawmax

# Take screenshot of initial state
take_screenshot /tmp/task_initial.png
echo "Initial state screenshot saved to /tmp/task_initial.png"

echo "=== Task setup complete ==="