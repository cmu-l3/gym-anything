#!/bin/bash
set -e
echo "=== Setting up create_digital_logic_circuit task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Create Diagrams directory if it doesn't exist
mkdir -p /home/ga/Diagrams
chown ga:ga /home/ga/Diagrams

# Clean up any previous run artifacts
rm -f /home/ga/Diagrams/full_adder_circuit.eddx
rm -f /home/ga/Diagrams/full_adder_circuit.png

# Kill any running EdrawMax instances to ensure clean state
kill_edrawmax

# Launch EdrawMax (opens to Home/Template screen)
echo "Launching EdrawMax..."
launch_edrawmax

# Wait for EdrawMax to fully load
wait_for_edrawmax 90

# Dismiss startup dialogs (Account Login, File Recovery, Banners)
dismiss_edrawmax_dialogs

# Maximize the window for better visibility
maximize_edrawmax

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="