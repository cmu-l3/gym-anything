#!/bin/bash
# Task setup: create_version
# Navigates Firefox to the Mobile Banking App project versions settings page.

source /workspace/scripts/task_utils.sh

echo "=== Setting up create_version task ==="

wait_for_openproject

launch_firefox_to "http://localhost:8080/projects/mobile-banking-app/settings/versions" 5

take_screenshot /tmp/task_create_version_start.png

echo "=== Task setup complete: create_version ==="
