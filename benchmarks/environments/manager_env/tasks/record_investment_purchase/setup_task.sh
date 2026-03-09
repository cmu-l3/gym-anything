#!/bin/bash
echo "=== Setting up record_investment_purchase task ==="

source /workspace/scripts/task_utils.sh

# Ensure Manager is running
wait_for_manager 60

# Record start time
date +%s > /tmp/task_start_time.txt

# Record initial state: Check if Investments module is already enabled (should not be)
# We will check if the endpoint is accessible or if it appears in the tabs list.
# For now, we assume standard clean state from setup_manager.sh where it is disabled.

# Open Manager.io at the Dashboard (Summary)
# We do NOT navigate to a specific module because the user must find Settings.
echo "Opening Manager.io at Dashboard..."
open_manager_at "" ""

# Take initial screenshot
sleep 5
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="