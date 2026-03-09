#!/bin/bash
echo "=== Setting up create_uml_component_diagram task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure clean state by removing previous output files
rm -f /home/ga/Documents/ecommerce_component_diagram.eddx 2>/dev/null || true
rm -f /home/ga/Documents/ecommerce_component_diagram.png 2>/dev/null || true

# Kill any existing EdrawMax instances to ensure fresh start
echo "Killing any existing EdrawMax processes..."
kill_edrawmax

# Launch EdrawMax (no file argument -> opens Home/Template screen)
echo "Launching EdrawMax..."
launch_edrawmax

# Wait for EdrawMax to fully load
wait_for_edrawmax 90

# Dismiss startup dialogs (Account Login, File Recovery, etc.)
dismiss_edrawmax_dialogs

# Maximize the window for better agent visibility
maximize_edrawmax

# Take a screenshot of the initial state
take_screenshot /tmp/task_initial.png
echo "Initial state screenshot saved to /tmp/task_initial.png"

echo "=== Task setup complete ==="