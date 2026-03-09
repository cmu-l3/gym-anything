#!/bin/bash
# Task setup: create_project
# Navigates Firefox to the New Project form.

source /workspace/scripts/task_utils.sh

echo "=== Setting up create_project task ==="

wait_for_openproject

launch_firefox_to "http://localhost:8080/projects/new" 5

take_screenshot /tmp/task_create_project_start.png

echo "=== Task setup complete: create_project ==="
