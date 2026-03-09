#!/bin/bash
set -e
echo "=== Setting up Create BowTie Risk Diagram task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Clean up any previous run artifacts
rm -f /home/ga/Documents/ransomware_bowtie.eddx
rm -f /home/ga/Documents/ransomware_bowtie.pdf
rm -f /tmp/task_result.json

# 3. Ensure EdrawMax is not running
kill_edrawmax

# 4. Launch EdrawMax to the Home/New screen
# We do not open a template because the agent must create this from scratch or find a template themselves.
echo "Launching EdrawMax..."
launch_edrawmax

# 5. Wait for application to be ready
wait_for_edrawmax 90

# 6. Dismiss any startup dialogs (Login, Recovery, etc.)
dismiss_edrawmax_dialogs

# 7. Maximize window
maximize_edrawmax

# 8. Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="