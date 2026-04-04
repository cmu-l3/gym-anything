#!/bin/bash
# Task setup: log_time
# Finds the biometric login work package and navigates to it.

source /workspace/scripts/task_utils.sh

echo "=== Setting up log_time task ==="

wait_for_openproject

# Get work package ID
WP_ID=$(get_wp_id "mobile-banking-app" "biometric login")

if [ -n "$WP_ID" ]; then
    echo "Found work package ID: $WP_ID"
    launch_firefox_to "http://localhost:8080/projects/mobile-banking-app/work_packages/${WP_ID}/activity" 5
else
    echo "Warning: Could not find WP ID, navigating to work packages list"
    launch_firefox_to "http://localhost:8080/projects/mobile-banking-app/work_packages" 5
fi

take_screenshot /tmp/task_log_time_start.png

echo "=== Task setup complete: log_time ==="
