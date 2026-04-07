#!/bin/bash
set -e
echo "=== Setting up create_saved_query task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure OpenProject is reachable
wait_for_openproject

# 1. CLEANUP: Delete any existing query with the target name to prevent false positives
echo "Cleaning up any existing queries..."
op_rails "Query.where(name: 'Bobs Backlog Items').destroy_all" 2>/dev/null || true

# 2. NAVIGATE: Launch Firefox to the Work Packages list
# This saves the agent from navigating from the home page
echo "Launching Firefox..."
launch_firefox_to "http://localhost:8080/projects/ecommerce-platform/work_packages" 8

# 3. SCREENSHOT: Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="