#!/bin/bash
set -e
echo "=== Setting up Lab Pack Chemical Classification Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 2. Clean up previous artifacts
rm -f /home/ga/Documents/lab_pack_inventory.csv 2>/dev/null || true

# 3. Ensure Firefox is running and navigated to CAMEO Chemicals
# We use the utility function to launch/focus
launch_firefox_to_url "https://cameochemicals.noaa.gov/" "ga"

# 4. Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="