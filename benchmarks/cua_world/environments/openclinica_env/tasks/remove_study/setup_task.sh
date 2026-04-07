#!/bin/bash
echo "=== Setting up remove_study task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure the studies exist and are in the expected starting state
echo "Enforcing baseline study statuses..."

# CV-REG-2023 should be Available (1)
oc_query "UPDATE study SET status_id = 1 WHERE unique_identifier = 'CV-REG-2023'" 2>/dev/null || true

# DM-TRIAL-2024 should be Available (1)
oc_query "UPDATE study SET status_id = 1 WHERE unique_identifier = 'DM-TRIAL-2024'" 2>/dev/null || true

# AP-PILOT-2022 should be Completed (4)
oc_query "UPDATE study SET status_id = 4 WHERE unique_identifier = 'AP-PILOT-2022'" 2>/dev/null || true

# 2. Record the initial baseline statuses for verification
CV_STATUS=$(oc_query "SELECT status_id FROM study WHERE unique_identifier = 'CV-REG-2023' LIMIT 1" 2>/dev/null || echo "1")
DM_STATUS=$(oc_query "SELECT status_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' LIMIT 1" 2>/dev/null || echo "1")
AP_STATUS=$(oc_query "SELECT status_id FROM study WHERE unique_identifier = 'AP-PILOT-2022' LIMIT 1" 2>/dev/null || echo "4")

echo "${CV_STATUS}" > /tmp/baseline_cv_status.txt
echo "${DM_STATUS}" > /tmp/baseline_dm_status.txt
echo "${AP_STATUS}" > /tmp/baseline_ap_status.txt

# 3. Record task start time and audit event count (for anti-gaming)
date +%s > /tmp/task_start_time.txt
AUDIT_COUNT=$(oc_query "SELECT COUNT(*) FROM audit_event" 2>/dev/null || echo "0")
echo "${AUDIT_COUNT}" > /tmp/baseline_audit_count.txt

# Generate integrity nonce
NONCE=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
echo "${NONCE}" > /tmp/result_nonce
chmod 644 /tmp/result_nonce

# 4. Browser Setup - Open to OpenClinica Main Menu
echo "Setting up Firefox..."
if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox 'http://localhost:8080/OpenClinica/MainMenu' > /tmp/firefox_task.log 2>&1 &
    sleep 5
fi

# Wait for window to appear and maximize
wait_for_window "firefox\|mozilla\|OpenClinica" 30
ensure_logged_in
focus_firefox
sleep 1

# Take initial screenshot for evidence
take_screenshot /tmp/task_start_screenshot.png ga

echo "=== remove_study setup complete ==="