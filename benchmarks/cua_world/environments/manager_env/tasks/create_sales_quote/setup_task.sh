#!/bin/bash
set -e
echo "=== Setting up create_sales_quote task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure Manager is running
wait_for_manager 60

# We explicitly do NOT enable Sales Quotes here. 
# The agent must do it. By default (from setup_data.sh), 
# Sales Quotes is NOT in the enabled tabs list.

# Open Firefox at the Manager.io Summary page (Northwind)
# We use the generic opener but point to the summary dashboard
echo "Opening Manager.io..."
open_manager_at "summary"

# Capture initial state screenshot
sleep 5
echo "Capturing initial state..."
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="