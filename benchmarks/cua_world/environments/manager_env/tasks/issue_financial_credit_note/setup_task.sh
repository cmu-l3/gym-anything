#!/bin/bash
# Setup script for issue_financial_credit_note

echo "=== Setting up task: Issue Financial Credit Note ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure Manager is running
wait_for_manager 60

# 2. Record start time for anti-gaming
date +%s > /tmp/manager_task_start_time

# 3. Open Manager at the Dashboard (Summary) to force navigation to Settings
# We do NOT want to open directly to Credit Notes, as part of the task is 
# navigating to Settings first.
echo "Opening Manager.io at Dashboard..."
open_manager_at "summary"

# 4. Take initial screenshot
sleep 5
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="