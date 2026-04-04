#!/bin/bash
# Setup script for implement_late_fee_policy task in Manager.io

echo "=== Setting up implement_late_fee_policy task ==="

source /workspace/scripts/task_utils.sh

# Ensure Manager.io is accessible
wait_for_manager 60

# Record task start time
date +%s > /tmp/manager_task_start_time

# Open Manager.io at the Summary page (neutral starting point)
# This forces the agent to navigate to Settings themselves
echo "Opening Manager.io Summary page..."
open_manager_at "summary"

# Capture initial state screenshot
sleep 5
take_screenshot /tmp/task_initial.png

echo ""
echo "=== Setup Complete ==="
echo "TASK: Implement Late Fee Policy"
echo "1. Settings > Chart of Accounts > New Account ('Late Fees Collected', Income)"
echo "2. Settings > Non-inventory Items > New Item ('Late Fee', Code: LATE, Price: 50.00, Account: Late Fees Collected)"
echo "3. Sales Invoices > New Invoice (Customer: Alfreds Futterkiste, Item: Late Fee)"