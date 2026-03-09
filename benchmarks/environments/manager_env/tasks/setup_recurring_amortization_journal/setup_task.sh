#!/bin/bash
echo "=== Setting up Recurring Amortization Task ==="

source /workspace/scripts/task_utils.sh

# Ensure Manager is ready
wait_for_manager 60

# Record task start time
date +%s > /tmp/task_start_time.txt

# Open Manager.io at the Settings page
# We use the 'settings' module key defined in navigate_manager.py
echo "Opening Manager.io at Settings..."
open_manager_at "settings"

# Capture initial state screenshot
sleep 5
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="