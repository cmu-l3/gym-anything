#!/bin/bash
# Setup script for create_sales_order task
# Starts Manager.io and opens Firefox at the Summary page.
# Ensures 'Sales Orders' is NOT enabled initially (standard state).

set -e
echo "=== Setting up create_sales_order task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Ensure Manager.io is running and accessible
wait_for_manager 60

# Record task start time
date +%s > /tmp/task_start_time.txt

# Open Manager.io at the Summary page (Business Dashboard)
# We do NOT use 'open_manager_at' with a specific module because
# the agent needs to find the module is missing and enable it.
echo "Opening Manager.io at Summary page..."

# Kill existing Firefox
pkill -f firefox 2>/dev/null || true
sleep 2

# Start Firefox at the base URL (which redirects to the business if last used, or business list)
# navigate_manager.py handles login and selecting Northwind
python3 /workspace/scripts/navigate_manager.py "summary"

# Ensure window is maximized
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Verify initial state: Take screenshot
echo "Capturing initial state..."
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="