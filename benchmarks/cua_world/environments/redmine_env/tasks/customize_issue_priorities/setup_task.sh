#!/bin/bash
set -euo pipefail
source /workspace/scripts/task_utils.sh

echo "=== Setting up customize_issue_priorities task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Redmine is reachable
wait_for_http "$REDMINE_BASE_URL/login" 120

# Login as admin and navigate to Administration -> Enumerations
# We go directly to the Enumerations page to set the context
TARGET_URL="$REDMINE_BASE_URL/enumerations"

echo "Logging in and navigating to $TARGET_URL..."
ensure_redmine_logged_in "$TARGET_URL"

# Wait for the page to load
sleep 5

# Take initial screenshot
take_screenshot "/tmp/task_initial.png"

echo "=== Task setup complete ==="