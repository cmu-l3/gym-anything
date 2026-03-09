#!/bin/bash
echo "=== Setting up create_project task ==="

# Clean up previous task files
rm -f /tmp/create_project_result.json 2>/dev/null || true
rm -f /tmp/initial_project_count 2>/dev/null || true

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record initial project count
INITIAL_COUNT=$(get_project_count)
echo "${INITIAL_COUNT:-0}" > /tmp/initial_project_count
echo "Initial project count: ${INITIAL_COUNT:-0}"

# Ensure Firefox is running at the login page
ensure_firefox_running "${SCINOTE_URL}/users/sign_in"

# Wait for page to load
sleep 3

# Take baseline screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "Task: Create a new project named 'Protein Crystallization Study'"
