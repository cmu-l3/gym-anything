#!/bin/bash
# Setup script for acquire_fixed_asset_via_invoice
# Ensures Manager is running and opens at the Summary page.
# The Fixed Assets module is disabled by default in the Northwind setup.

echo "=== Setting up acquire_fixed_asset_via_invoice task ==="

source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Ensure Manager.io is accessible
wait_for_manager 60

# We intentionally DO NOT enable Fixed Assets here. 
# The user must do it as part of the task.
# We just ensure we are at the Summary page.

echo "Opening Manager.io at Summary page..."
open_manager_at "summary"

# Take initial screenshot for evidence
sleep 5
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="