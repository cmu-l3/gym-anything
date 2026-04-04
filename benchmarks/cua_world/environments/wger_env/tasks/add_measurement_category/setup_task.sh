#!/bin/bash
# Task setup: add_measurement_category
# Navigates the browser to the measurements overview page.
# The agent will create a new category "Neck" and add a 38.5 cm entry.

source /workspace/scripts/task_utils.sh

echo "=== Setting up add_measurement_category task ==="

# Ensure wger is responding
wait_for_wger_page

# Launch Firefox (handles cold start + snap permissions)
launch_firefox_to "http://localhost/en/measurement/" 5

# Take a starting screenshot
take_screenshot /tmp/task_add_measurement_category_start.png

echo "=== Task setup complete: add_measurement_category ==="
