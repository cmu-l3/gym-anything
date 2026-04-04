#!/bin/bash
# Setup script for customize_email_template task
# Opens Manager.io at the Settings page

echo "=== Setting up customize_email_template task ==="

source /workspace/scripts/task_utils.sh

# Ensure Manager.io is accessible
wait_for_manager 60

# Record task start time
date +%s > /tmp/task_start_time.txt

# Open Manager.io at the Settings module
# The navigation script supports "settings" which maps to the Settings tab in the sidebar
echo "Opening Manager.io Settings..."
open_manager_at "settings"

# Wait a bit for the page to load and focus to settle
sleep 5

# Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "Task: Customize Sales Invoice Email Template"
echo "Target: Settings > Email Templates > Sales Invoice"