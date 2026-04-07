#!/bin/bash
echo "=== Setting up update_study_parameters task ==="

source /workspace/scripts/task_utils.sh

# 1. Wait for OpenClinica
if ! verify_openclinica_ready 60; then
    echo "ERROR: OpenClinica is not responding"
    docker restart oc-app 2>/dev/null || true
    sleep 30
    verify_openclinica_ready 120 || { echo "FATAL: OpenClinica not available"; exit 1; }
fi

# 2. Get study_id for DM-TRIAL-2024
STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' LIMIT 1" 2>/dev/null || echo "")
if [ -z "$STUDY_ID" ]; then
    echo "ERROR: Study DM-TRIAL-2024 not found. Environment setup may have failed."
    exit 1
fi
echo "Found study DM-TRIAL-2024 with study_id=$STUDY_ID"

# 3. Reset study parameters to known default values
echo "Resetting study parameters to defaults..."
# Update the main parameters
oc_query "UPDATE study SET
    collect_dob = '1',
    gender_required = true,
    person_id_shown_on_crf = true,
    interviewer_name_required = false,
    interview_date_required = false,
    date_updated = NULL
WHERE study_id = $STUDY_ID;" 2>/dev/null || {
    # Fallback in case of type differences (e.g. chars vs bools in some schema versions)
    echo "Note: Standard bulk update failed, trying individual updates..."
    oc_query "UPDATE study SET collect_dob = '1' WHERE study_id = $STUDY_ID" 2>/dev/null || true
    oc_query "UPDATE study SET gender_required = 't' WHERE study_id = $STUDY_ID" 2>/dev/null || true
    oc_query "UPDATE study SET person_id_shown_on_crf = 't' WHERE study_id = $STUDY_ID" 2>/dev/null || true
    oc_query "UPDATE study SET interviewer_name_required = 'f' WHERE study_id = $STUDY_ID" 2>/dev/null || true
    oc_query "UPDATE study SET interview_date_required = 'f' WHERE study_id = $STUDY_ID" 2>/dev/null || true
}

# 4. Record baseline parameter values and timestamp
INITIAL_PARAMS=$(oc_query "SELECT collect_dob, gender_required, person_id_shown_on_crf, interviewer_name_required, interview_date_required FROM study WHERE study_id = $STUDY_ID" 2>/dev/null || echo "QUERY_FAILED")
echo "$INITIAL_PARAMS" > /tmp/initial_study_params.txt
echo "Initial parameters: $INITIAL_PARAMS"

date +%s > /tmp/task_start_time.txt
AUDIT_BASELINE=$(get_recent_audit_count 15 2>/dev/null || echo "0")
echo "${AUDIT_BASELINE:-0}" > /tmp/audit_baseline_count

# 5. Ensure root user's active study is set to DM-TRIAL-2024 for immediate task readiness
oc_query "UPDATE study_user_role SET study_id = $STUDY_ID WHERE user_name = 'root'" 2>/dev/null || true

# 6. Start Firefox and log in
if ! pgrep -f firefox > /dev/null 2>&1; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080/OpenClinica/MainMenu' &" 2>/dev/null
    sleep 8
fi

wait_for_window "firefox\|Mozilla" 30 || {
    echo "WARNING: Firefox window not detected, trying to launch again"
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080/OpenClinica/MainMenu' &" 2>/dev/null
    sleep 10
}

DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

ensure_logged_in
sleep 2
switch_active_study "DM-TRIAL-2024"
sleep 2

# Take screenshot of initial state
take_screenshot /tmp/task_initial_state.png

# Generate integrity nonce
NONCE=$(head -c 16 /dev/urandom | xxd -p)
echo "$NONCE" > /tmp/result_nonce

echo "=== Task setup complete ==="