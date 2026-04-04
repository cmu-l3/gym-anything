#!/bin/bash
# setup_task.sh - Pre-task hook for spill_neutralization_agent_lookup
set -e

echo "=== Setting up Spill Neutralization Agent Lookup Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Record Task Start Time (Anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 2. Clean Environment
# Kill existing Firefox to ensure clean state
kill_firefox "ga"

# Ensure output directory exists and is empty of previous results
sudo -u ga mkdir -p /home/ga/Documents
rm -f /home/ga/Documents/neutralizer_inventory.csv
echo "Cleaned previous output files."

# 3. Launch Firefox
# Launch directly to CAMEO Chemicals homepage
launch_firefox_to_url "https://cameochemicals.noaa.gov/" "ga"

# 4. Final Setup Verification
# Ensure window is actually there and maximized
maximize_firefox

# 5. Capture Initial Evidence
take_screenshot /tmp/task_initial.png
echo "Initial screenshot captured."

echo "=== Task Setup Complete ==="