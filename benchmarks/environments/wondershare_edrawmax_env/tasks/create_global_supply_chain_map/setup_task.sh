#!/bin/bash
echo "=== Setting up create_global_supply_chain_map task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Kill any running EdrawMax instances to ensure clean state
echo "Killing any existing EdrawMax processes..."
kill_edrawmax

# Clean up previous run artifacts
rm -f /home/ga/Documents/phoenix_supply_chain.eddx 2>/dev/null || true
rm -f /home/ga/Documents/phoenix_supply_chain.png 2>/dev/null || true

# Launch EdrawMax (fresh start, no file loaded)
echo "Launching EdrawMax..."
launch_edrawmax

# Wait for EdrawMax to fully load
wait_for_edrawmax 90

# Dismiss startup dialogs (Account Login, File Recovery, Notifications)
dismiss_edrawmax_dialogs

# Maximize the window for best agent visibility
maximize_edrawmax

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png
echo "Initial state screenshot saved to /tmp/task_initial.png"

echo "=== Task setup complete ==="
echo "EdrawMax is open. Agent should create a World Map diagram."