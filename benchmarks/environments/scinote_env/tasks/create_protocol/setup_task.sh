#!/bin/bash
echo "=== Setting up create_protocol task ==="

# Clean up previous task files
rm -f /tmp/create_protocol_result.json 2>/dev/null || true
rm -f /tmp/initial_protocol_count 2>/dev/null || true

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record initial protocol count (only team/public protocols, not task-level)
INITIAL_COUNT=$(get_protocol_count)
echo "${INITIAL_COUNT:-0}" > /tmp/initial_protocol_count
echo "Initial protocol count: ${INITIAL_COUNT:-0}"

# Ensure Firefox is running at the login page
ensure_firefox_running "${SCINOTE_URL}/users/sign_in"

sleep 3
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "Task: Create a new protocol named 'Western Blot Analysis v2'"
