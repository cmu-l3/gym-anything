#!/bin/bash
echo "=== Setting up create_user_account task ==="

source /workspace/scripts/task_utils.sh

INITIAL_COUNT=$(get_user_count)
echo "$INITIAL_COUNT" > /tmp/initial_user_count
echo "Initial user count: $INITIAL_COUNT"

if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox 'http://localhost:8080/OpenClinica/MainMenu' > /tmp/firefox_task.log 2>&1 &
    sleep 5
fi

wait_for_window "firefox\|mozilla\|OpenClinica" 30

# Verify login state - handles 404, login page, password reset
ensure_logged_in

# Switch the active study to Phase II Diabetes Trial in the browser
switch_active_study "DM-TRIAL-2024"

focus_firefox
sleep 1

DISPLAY=:1 xdotool mousemove 960 540 click 1 2>/dev/null || true
sleep 0.5
focus_firefox

# Record audit log baseline AFTER all setup navigation
AUDIT_BASELINE=$(get_recent_audit_count 15)
echo "$AUDIT_BASELINE" > /tmp/audit_baseline_count
echo "Audit log baseline after setup: $AUDIT_BASELINE"

# Generate integrity nonce to detect result file tampering
NONCE=$(generate_result_nonce)
echo "Result integrity nonce: $NONCE"

take_screenshot /tmp/task_start_screenshot.png

echo "=== create_user_account task setup complete ==="
