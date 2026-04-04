#!/bin/bash
# setup_task.sh - Pre-task hook for safer_solvent_substitution_screening

echo "=== Setting up Safer Solvent Substitution Screening Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time
echo "Task start time: $(cat /tmp/task_start_time)"

# Ensure output directory exists and is clean
sudo -u ga mkdir -p /home/ga/Documents
rm -f /home/ga/Documents/solvent_screening_matrix.txt 2>/dev/null || true

# Kill any existing Firefox instances
kill_firefox ga

# Launch Firefox to CAMEO Chemicals homepage
# This ensures the agent starts at the right place
launch_firefox_to_url "https://cameochemicals.noaa.gov/" ga 60

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

# Verify initial state
if [ -f /tmp/task_initial.png ]; then
    echo "Initial state capture successful"
else
    echo "WARNING: Failed to capture initial state"
fi

echo "=== Task Setup Complete ==="