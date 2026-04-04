#!/bin/bash
set -e
echo "=== Setting up create_investment_decision_tree task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure clean state: kill existing instances
kill_edrawmax

# Remove previous output files if they exist (prevent false positives)
rm -f /home/ga/Documents/build_vs_buy_tree.eddx
rm -f /home/ga/Documents/build_vs_buy_tree.png

# Launch EdrawMax (opens to Home/New screen)
echo "Launching EdrawMax..."
launch_edrawmax

# Wait for window to appear
wait_for_edrawmax 90

# Dismiss startup dialogs (Account Login, File Recovery)
dismiss_edrawmax_dialogs

# Maximize window (CRITICAL for agent visibility)
maximize_edrawmax

# Take screenshot of initial state (for evidence)
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="