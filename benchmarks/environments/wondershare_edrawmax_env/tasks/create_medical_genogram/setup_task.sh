#!/bin/bash
set -e
echo "=== Setting up create_medical_genogram task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure clean state: remove any previous output files
rm -f /home/ga/Diagrams/medical_genogram.eddx
rm -f /home/ga/Diagrams/medical_genogram.png

# Create Diagrams directory if it doesn't exist
mkdir -p /home/ga/Diagrams
chown ga:ga /home/ga/Diagrams

# Kill any running instances
kill_edrawmax

# Launch EdrawMax fresh (opens to Home/New screen)
echo "Launching EdrawMax..."
launch_edrawmax

# Wait for application to load
wait_for_edrawmax 90

# Dismiss startup dialogs (Login, Recovery, etc.)
dismiss_edrawmax_dialogs

# Maximize window for better visibility
maximize_edrawmax

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png
echo "Initial state screenshot captured: /tmp/task_initial.png"

echo "=== Task setup complete ==="