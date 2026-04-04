#!/bin/bash
# Task setup: add_work_package_comment
# Finds the Safari checkout bug work package and navigates to its activity.

source /workspace/scripts/task_utils.sh

echo "=== Setting up add_work_package_comment task ==="

wait_for_openproject

# Get work package ID
WP_ID=$(get_wp_id "ecommerce-platform" "mobile Safari")

if [ -n "$WP_ID" ]; then
    echo "Found work package ID: $WP_ID"
    launch_firefox_to "http://localhost:8080/projects/ecommerce-platform/work_packages/${WP_ID}/activity" 5
else
    echo "Warning: Could not find WP ID, navigating to work packages list"
    launch_firefox_to "http://localhost:8080/projects/ecommerce-platform/work_packages" 5
fi

take_screenshot /tmp/task_add_wp_comment_start.png

echo "=== Task setup complete: add_work_package_comment ==="
