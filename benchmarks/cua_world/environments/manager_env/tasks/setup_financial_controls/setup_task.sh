#!/bin/bash
# Setup script for setup_financial_controls task
# Starts Manager.io and ensures we are on the dashboard

echo "=== Setting up setup_financial_controls task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure Manager.io is running
wait_for_manager 60

# 2. Record Task Start Time
date +%s > /tmp/task_start_time.txt

# 3. Open Firefox at the Manager.io Dashboard (Summary)
# We deliberately start at Summary so the agent must find "Settings"
echo "Opening Manager.io Dashboard..."
open_manager_at "summary"

# 4. Record Initial State (Optional, but good for debugging)
# We can try to fetch the current lock date to confirm it's not already set
# (Requires extracting business key, which is complex in bash, so we skip rigorous pre-check 
# and rely on the fact that a fresh env has no lock date)

echo "=== Setup complete ==="