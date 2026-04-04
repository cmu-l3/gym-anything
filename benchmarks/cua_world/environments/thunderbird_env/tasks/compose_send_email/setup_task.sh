#!/bin/bash
echo "=== Setting up compose_send_email task ==="

source /workspace/scripts/task_utils.sh

# Record initial state of Drafts folder
INITIAL_DRAFTS_COUNT=$(count_emails_in_mbox "${LOCAL_MAIL_DIR}/Drafts")
echo "$INITIAL_DRAFTS_COUNT" > /tmp/initial_drafts_count
echo "Initial drafts count: $INITIAL_DRAFTS_COUNT"

# Start Thunderbird if not running
start_thunderbird

# Wait for Thunderbird window to appear
wait_for_thunderbird_window 30

# Maximize the window
sleep 3
maximize_thunderbird

# Take initial screenshot
take_screenshot /tmp/thunderbird_task_start.png

echo "=== compose_send_email task setup complete ==="
