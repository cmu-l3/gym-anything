#!/bin/bash
echo "=== Setting up record_loan_repayment_split task ==="

source /workspace/scripts/task_utils.sh

# Ensure Manager.io is running and accessible
wait_for_manager 60

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure we start fresh - kill any existing firefox instances
pkill -f firefox 2>/dev/null || true
sleep 2

# Open Manager.io directly to the Northwind Traders business (if possible) or Login
# We use the open_manager_at helper which handles login and navigation
# We'll start at the Summary page to let the agent find Settings
echo "Opening Manager.io at Summary page..."
open_manager_at "summary"

# Capture initial state screenshot
sleep 15
echo "Capturing initial state..."
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="