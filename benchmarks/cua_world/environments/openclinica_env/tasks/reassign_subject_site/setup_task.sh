#!/bin/bash
echo "=== Setting up reassign_subject_site task ==="

source /workspace/scripts/task_utils.sh

# Get Parent Study ID
DM_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' AND status_id != 3 LIMIT 1")
if [ -z "$DM_STUDY_ID" ]; then
    echo "ERROR: Phase II Diabetes Trial not found"
    exit 1
fi
echo "Parent Study ID: $DM_STUDY_ID"

# 1. Ensure 'Boston Clinic' Site Exists
SITE_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-BOS-001' AND status_id != 3 LIMIT 1")
if [ -z "$SITE_ID" ]; then
    echo "Creating Boston Clinic site..."
    oc_query "INSERT INTO study (name, unique_identifier, status_id, owner_id, date_created, parent_study_id, protocol_type, oc_oid) VALUES ('Boston Clinic', 'DM-BOS-001', 1, 1, NOW(), $DM_STUDY_ID, 'observational', 'S_DMBOS001')"
    SITE_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-BOS-001' AND status_id != 3 LIMIT 1")
fi
echo "Boston Clinic Site ID: $SITE_ID"

# 2. Clean up any existing BOS-101 record
echo "Cleaning up any pre-existing BOS-101..."
oc_query "DELETE FROM study_subject WHERE label = 'BOS-101'" 2>/dev/null || true

# 3. Ensure DM-101 exists in the parent study
SS_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = 'DM-101' AND status_id != 3 LIMIT 1")
if [ -z "$SS_ID" ]; then
    echo "Creating DM-101 subject..."
    oc_query "INSERT INTO subject (date_of_birth, gender, status_id, owner_id, date_created, unique_identifier) VALUES ('1980-01-01', 'f', 1, 1, NOW(), 'SUBJ_101')"
    SUBJ_ID=$(oc_query "SELECT subject_id FROM subject WHERE unique_identifier = 'SUBJ_101' LIMIT 1")
    oc_query "INSERT INTO study_subject (label, subject_id, study_id, status_id, owner_id, date_created, enrollment_date, oc_oid) VALUES ('DM-101', $SUBJ_ID, $DM_STUDY_ID, 1, 1, NOW(), NOW(), 'SS_DM101')"
    SS_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = 'DM-101' AND status_id != 3 LIMIT 1")
else
    echo "Resetting DM-101 to parent study..."
    oc_query "UPDATE study_subject SET study_id = $DM_STUDY_ID, label = 'DM-101' WHERE study_subject_id = $SS_ID"
fi
echo "DM-101 Subject ID: $SS_ID"

# Record Baselines
AUDIT_BASELINE=$(get_recent_audit_count 15)
echo "${AUDIT_BASELINE:-0}" > /tmp/audit_baseline_count
date +%s > /tmp/task_start_timestamp

# Ensure Firefox is running and logged in
if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox 'http://localhost:8080/OpenClinica/MainMenu' > /tmp/firefox_task.log 2>&1 &
    sleep 5
fi

wait_for_window "firefox\|mozilla\|OpenClinica" 30
ensure_logged_in
switch_active_study "DM-TRIAL-2024"
focus_firefox
sleep 1

NONCE=$(generate_result_nonce)
echo "Nonce: $NONCE"

take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup complete ==="