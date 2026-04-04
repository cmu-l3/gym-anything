#!/bin/bash
# Setup script for Create Appointment Status task

echo "=== Setting up Create Appointment Status Task ==="

source /workspace/scripts/task_utils.sh

# Record timestamp for anti-gaming
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/task_start_timestamp

# 1. Clean up: Ensure status 'V' does not exist
echo "Cleaning up any existing 'V' status..."
oscar_query "DELETE FROM appointment_status WHERE status='V'" 2>/dev/null || true

# 2. Record initial count of appointment statuses
INITIAL_COUNT=$(oscar_query "SELECT COUNT(*) FROM appointment_status" || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_status_count
echo "Initial appointment status count: $INITIAL_COUNT"

# 3. Open Firefox on OSCAR login page
# Using the helper from task_utils.sh which handles window focusing and maximization
ensure_firefox_on_oscar

# 4. Take initial screenshot
take_screenshot /tmp/task_initial_screenshot.png

echo ""
echo "=== Setup Complete ==="
echo "Task: Create Appointment Status 'V' (Vitals Done) - Green"
echo "Login credentials: oscardoc / oscar / 1117"