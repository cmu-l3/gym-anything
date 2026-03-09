#!/bin/bash
echo "=== Setting up create_crf task ==="

source /workspace/scripts/task_utils.sh

INITIAL_COUNT=$(get_crf_count)
echo "$INITIAL_COUNT" > /tmp/initial_crf_count
echo "Initial CRF count: $INITIAL_COUNT"

# Copy the CRF template to an accessible location for the user
if [ -f "/workspace/data/sample_crf.xls" ]; then
    cp /workspace/data/sample_crf.xls /home/ga/sample_crf.xls
    chown ga:ga /home/ga/sample_crf.xls
    chmod 644 /home/ga/sample_crf.xls
    echo "CRF template copied to /home/ga/sample_crf.xls"
else
    echo "WARNING: CRF template not found at /workspace/data/sample_crf.xls"
fi

if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox 'http://localhost:8080/OpenClinica/MainMenu' > /tmp/firefox_task.log 2>&1 &
    sleep 5
fi

wait_for_window "firefox\|mozilla\|OpenClinica" 30

# Verify login state - handles 404, login page, password reset
ensure_logged_in

# CRF creation is study-independent but switch to DM trial for consistency
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

echo "=== create_crf task setup complete ==="
