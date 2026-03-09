#!/bin/bash
echo "=== Setting up Track Project Expenses task ==="

source /workspace/scripts/task_utils.sh

# Ensure Manager.io is accessible
wait_for_manager 60

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Record initial counts to ensure we are starting fresh
# We can't easily query the internal DB, but we can assume standard Northwind state
# which has 0 projects initially.
echo "0" > /tmp/initial_project_count.txt

# Open Manager.io at the Summary page
# We do NOT navigate to specific modules because the agent needs to enable one
echo "Opening Manager.io at Summary..."
open_manager_at "summary"

# Ensure window is maximized
sleep 5
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="