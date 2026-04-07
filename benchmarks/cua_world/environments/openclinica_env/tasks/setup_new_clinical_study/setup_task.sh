#!/bin/bash
echo "=== Setting up setup_new_clinical_study task ==="

source /workspace/scripts/task_utils.sh

# 1. Clean up any pre-existing study with the target unique_identifier
TARGET_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'PK-HV-001' LIMIT 1" 2>/dev/null || echo "")

if [ -n "$TARGET_STUDY_ID" ]; then
    echo "Found pre-existing study PK-HV-001 (id=$TARGET_STUDY_ID). Removing for a clean state..."
    # Cascade delete to ensure clean slate
    oc_query "DELETE FROM study_user_role WHERE study_id = $TARGET_STUDY_ID" 2>/dev/null || true
    oc_query "DELETE FROM study_event_definition WHERE study_id = $TARGET_STUDY_ID" 2>/dev/null || true
    oc_query "DELETE FROM study WHERE study_id = $TARGET_STUDY_ID" 2>/dev/null || true
    echo "Clean up of pre-existing study complete."
fi

# 2. Ensure user 'mrivera' exists in the system so the agent can assign them
MRIVERA_EXISTS=$(oc_query "SELECT COUNT(*) FROM user_account WHERE user_name = 'mrivera'" 2>/dev/null || echo "0")
if [ "${MRIVERA_EXISTS:-0}" = "0" ]; then
    echo "Creating 'mrivera' user account..."
    oc_query "INSERT INTO user_account (user_name, passwd, first_name, last_name, email, status_id, owner_id, date_created)
              VALUES ('mrivera', 'da39a3ee5e6b4b0d3255bfef95601890afd80709', 'Maria', 'Rivera', 'mrivera@clinical.org', 1, 1, NOW())" 2>/dev/null || true
else
    echo "User 'mrivera' already exists."
fi

# 3. Record baselines for anti-gaming (ensure they actually create a new row)
MAX_STUDY_ID=$(oc_query "SELECT COALESCE(MAX(study_id), 0) FROM study" 2>/dev/null || echo "0")
echo "$MAX_STUDY_ID" > /tmp/baseline_max_study_id
echo "Baseline max study_id: $MAX_STUDY_ID"

AUDIT_BASELINE=$(get_recent_audit_count 15)
echo "${AUDIT_BASELINE:-0}" > /tmp/audit_baseline_count
echo "Audit log baseline: ${AUDIT_BASELINE:-0}"

NONCE=$(generate_result_nonce)
echo "Integrity Nonce: $NONCE"

date +%s > /tmp/task_start_timestamp

# 4. Ensure Firefox is running and logged in
if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox 'http://localhost:8080/OpenClinica/MainMenu' > /tmp/firefox_task.log 2>&1 &
    sleep 5
fi

wait_for_window "firefox\|mozilla\|OpenClinica" 30
ensure_logged_in
focus_firefox
sleep 1

# Take initial screenshot showing the OpenClinica dashboard
take_screenshot /tmp/task_start_screenshot.png

echo "=== setup_new_clinical_study setup complete ==="