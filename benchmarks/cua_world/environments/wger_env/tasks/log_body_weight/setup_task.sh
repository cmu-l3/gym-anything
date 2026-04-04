#!/bin/bash
# Task setup: log_body_weight
# Navigates the browser to the body weight overview page.
# The agent will add a weight entry of 82.5 kg.

source /workspace/scripts/task_utils.sh

echo "=== Setting up log_body_weight task ==="

# Ensure wger is responding
wait_for_wger_page

# Launch Firefox (handles cold start + snap permissions)
launch_firefox_to "http://localhost/en/weight/overview/" 5

# Take a starting screenshot
take_screenshot /tmp/task_log_body_weight_start.png

echo "=== Task setup complete: log_body_weight ==="
