#!/bin/bash
# Task setup: update_work_package_status
# Finds the "Kubernetes cluster autoscaling" work package ID and navigates to it.

source /workspace/scripts/task_utils.sh

echo "=== Setting up update_work_package_status task ==="

wait_for_openproject

# Get work package ID from seed data
WP_ID=$(get_wp_id "devops-automation" "Kubernetes cluster")

if [ -n "$WP_ID" ]; then
    echo "Found work package ID: $WP_ID"
    launch_firefox_to "http://localhost:8080/projects/devops-automation/work_packages/${WP_ID}/activity" 5
else
    echo "Warning: Could not find WP ID, navigating to work packages list"
    launch_firefox_to "http://localhost:8080/projects/devops-automation/work_packages" 5
fi

take_screenshot /tmp/task_update_wp_status_start.png

echo "=== Task setup complete: update_work_package_status ==="
