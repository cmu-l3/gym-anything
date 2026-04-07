#!/bin/bash
echo "=== Setting up assign_study_role task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Ensure Target Study Exists (CV-REG-2023)
CV_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'CV-REG-2023' AND status_id != 3 LIMIT 1")
if [ -z "$CV_STUDY_ID" ]; then
    echo "Creating CV-REG-2023 study..."
    oc_query "INSERT INTO study (name, unique_identifier, status_id, owner_id, date_created, protocol_type, principal_investigator, oc_oid) VALUES ('Cardiovascular Outcomes Registry', 'CV-REG-2023', 1, 1, NOW(), 'observational', 'Dr. Michael Rivera', 'S_CVREG23')" 2>/dev/null || true
    CV_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'CV-REG-2023' LIMIT 1")
fi
echo "CV Registry study_id: $CV_STUDY_ID"

# 2. Ensure monitor_user exists
USER_EXISTS=$(oc_query "SELECT COUNT(*) FROM user_account WHERE user_name = 'monitor_user'")
if [ "${USER_EXISTS:-0}" = "0" ]; then
    echo "Creating monitor_user..."
    # SHA-1 of 'Monitor1!' = 6f8cc50c2fa4b0cbabf37ecf01fbd008c2a86cba
    oc_query "INSERT INTO user_account (user_name, passwd, first_name, last_name, email, status_id, owner_id, date_created, institutional_affiliation, user_type_id, enabled, account_non_locked) VALUES ('monitor_user', '6f8cc50c2fa4b0cbabf37ecf01fbd008c2a86cba', 'Jane', 'Monitor', 'jane@cro.org', 1, 1, NOW(), 'Acme CRO', 2, true, true)" 2>/dev/null || true
fi

# 3. Clean up any existing role for monitor_user in CV-REG-2023
echo "Cleaning pre-existing roles to guarantee a clean starting state..."
oc_query "DELETE FROM study_user_role WHERE user_name = 'monitor_user' AND study_id = $CV_STUDY_ID" 2>/dev/null || true

# 4. Record baselines and timestamps
TASK_START_TIME=$(date +%s)
echo "$TASK_START_TIME" > /tmp/task_start_time.txt
echo "$CV_STUDY_ID" > /tmp/target_study_id.txt

AUDIT_BASELINE=$(get_recent_audit_count 15 2>/dev/null || echo "0")
echo "${AUDIT_BASELINE:-0}" > /tmp/audit_baseline_count

NONCE=$(generate_result_nonce 2>/dev/null || echo $RANDOM)
echo "$NONCE" > /tmp/result_nonce

# 5. UI Setup
echo "Launching Firefox and focusing OpenClinica..."
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080/OpenClinica/MainMenu' &"
    sleep 5
fi

wait_for_window "firefox\|mozilla\|OpenClinica" 30 2>/dev/null || true
ensure_logged_in 2>/dev/null || true

# Navigate to root context to ensure clean UI state
focus_firefox 2>/dev/null || true
DISPLAY=:1 xdotool key ctrl+l 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool type --delay 20 'http://localhost:8080/OpenClinica/MainMenu' 2>/dev/null || true
DISPLAY=:1 xdotool key Return 2>/dev/null || true
sleep 5

take_screenshot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== Setup complete ==="