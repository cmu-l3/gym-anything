#!/bin/bash
echo "=== Setting up emergency_sae_logging task ==="

source /workspace/scripts/task_utils.sh

# 1. Get DM Trial study_id
DM_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' AND status_id != 3 LIMIT 1")
if [ -z "$DM_STUDY_ID" ]; then
    echo "ERROR: Phase II Diabetes Trial not found"
    exit 1
fi

# 2. Ensure DM-105 exists
DM105_SS_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = 'DM-105' AND study_id = $DM_STUDY_ID LIMIT 1")
if [ -z "$DM105_SS_ID" ]; then
    echo "Creating subject DM-105..."
    oc_query "INSERT INTO subject (date_of_birth, gender, status_id, date_created, owner_id) VALUES ('1960-05-12', 'm', 1, NOW(), 1)"
    SUBJ_ID=$(oc_query "SELECT subject_id FROM subject ORDER BY subject_id DESC LIMIT 1")
    oc_query "INSERT INTO study_subject (label, subject_id, study_id, status_id, enrollment_date, date_created, owner_id) VALUES ('DM-105', $SUBJ_ID, $DM_STUDY_ID, 1, CURRENT_DATE, NOW(), 1)"
    DM105_SS_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = 'DM-105' AND study_id = $DM_STUDY_ID LIMIT 1")
fi

# 3. Ensure "Unscheduled SAE" event def exists
SAE_SED_ID=$(oc_query "SELECT study_event_definition_id FROM study_event_definition WHERE name = 'Unscheduled SAE' AND study_id = $DM_STUDY_ID AND status_id != 3 LIMIT 1")
if [ -z "$SAE_SED_ID" ]; then
    echo "Creating Unscheduled SAE event definition..."
    oc_query "INSERT INTO study_event_definition (study_id, name, description, repeating, type, status_id, owner_id, date_created, oc_oid, ordinal) VALUES ($DM_STUDY_ID, 'Unscheduled SAE', 'Unscheduled event for Serious Adverse Events', false, 'Unscheduled', 1, 1, NOW(), 'SE_UNSCHED_SAE', 99)"
    SAE_SED_ID=$(oc_query "SELECT study_event_definition_id FROM study_event_definition WHERE name = 'Unscheduled SAE' AND study_id = $DM_STUDY_ID AND status_id != 3 LIMIT 1")
fi

# 4. Clean up existing events and notes for DM-105
oc_query "DELETE FROM discrepancy_note WHERE entity_type = 'studySubject' AND entity_id = $DM105_SS_ID" 2>/dev/null || true
oc_query "DELETE FROM study_event WHERE study_subject_id = $DM105_SS_ID AND study_event_definition_id = $SAE_SED_ID" 2>/dev/null || true

# 5. Baseline audit and timestamp
date +%s > /tmp/task_start_timestamp
AUDIT_BASELINE=$(get_recent_audit_count 15)
echo "${AUDIT_BASELINE:-0}" > /tmp/audit_baseline_count
generate_result_nonce > /tmp/result_nonce

# 6. Firefox setup
if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox 'http://localhost:8080/OpenClinica/MainMenu' > /tmp/firefox_task.log 2>&1 &
    sleep 5
fi

wait_for_window "firefox\|mozilla\|OpenClinica" 30
ensure_logged_in
switch_active_study "DM-TRIAL-2024"
focus_firefox
sleep 1

take_screenshot /tmp/task_start_screenshot.png
echo "=== Setup complete ==="