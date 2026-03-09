#!/bin/bash
echo "=== Setting up create_study task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record baseline state
INITIAL_COUNT=$(get_study_count)
echo "$INITIAL_COUNT" > /tmp/initial_study_count
echo "Initial study count: $INITIAL_COUNT"

# Ensure Firefox is running
if ! pgrep -f firefox > /dev/null; then
    echo "Firefox not running, starting..."
    DISPLAY=:1 firefox 'http://localhost:8080/OpenClinica/MainMenu' > /tmp/firefox_task.log 2>&1 &
    sleep 5
fi

# Wait for Firefox window
wait_for_window "firefox\|mozilla\|OpenClinica" 30

# Verify login state - handles 404, login page, password reset
ensure_logged_in

# Focus and maximize Firefox
focus_firefox
sleep 1

# Click center to ensure focus
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

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== create_study task setup complete ==="
