#!/bin/bash
echo "=== Setting up create_pneumatic_circuit_diagram task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Kill any running EdrawMax instances to ensure clean state
echo "Killing any existing EdrawMax processes..."
kill_edrawmax

# Remove any leftover output files from previous runs
rm -f /home/ga/Documents/pneumatic_clamp_circuit.eddx 2>/dev/null || true
rm -f /home/ga/Documents/pneumatic_clamp_circuit.png 2>/dev/null || true

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Launch EdrawMax fresh (no file argument - opens to home/new screen)
echo "Launching EdrawMax..."
launch_edrawmax

# Wait for EdrawMax to fully load
# This function (from task_utils.sh) waits for process + extra time for UI
wait_for_edrawmax 90

# Dismiss startup dialogs (Account Login and File Recovery)
# This is critical as these dialogs block the UI
dismiss_edrawmax_dialogs

# Maximize the window
maximize_edrawmax

# Take a screenshot to verify start state
take_screenshot /tmp/task_initial.png
echo "Start state screenshot saved to /tmp/task_initial.png"

echo "=== Task setup complete ==="
echo "EdrawMax is open. Agent should create a pneumatic circuit and save to ~/Documents/"