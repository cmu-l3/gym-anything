#!/bin/bash
set -e
echo "=== Setting up Configure User Custom Field Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for OpenProject to be ready
wait_for_openproject

# Clean up any existing "Employee ID" custom field to ensure fresh start
echo "Cleaning up previous state..."
op_rails "CustomField.where(name: 'Employee ID').destroy_all"

# Launch Firefox to the Administration overview or login page
# Using the administration/custom_fields path prompts login, which is good workflow
echo "Launching Firefox..."
launch_firefox_to "http://localhost:8080/admin/custom_fields" 5

# Ensure window is maximized
maximize_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="