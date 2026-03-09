#!/bin/bash
# Setup script for access_admin_system_info task

echo "=== Setting up access_admin_system_info task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Remove any pre-existing report file (ensure clean slate)
rm -f /home/ga/system_audit_report.txt

# Ensure Emoncms is running
wait_for_emoncms

# Launch Firefox to the main dashboard (logged in)
# The agent must find their way to the Admin panel from here
launch_firefox_to "http://localhost/" 8

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="