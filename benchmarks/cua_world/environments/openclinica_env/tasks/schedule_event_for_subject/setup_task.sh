#!/bin/bash
echo "=== Setting up schedule_event_for_subject task ==="

source /workspace/scripts/task_utils.sh

# Get the DM Trial study_id
DM_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' AND status_id != 3 LIMIT 1")
if [ -z "$DM_STUDY_ID" ]; then
    echo "ERROR: Phase II Diabetes Trial not found in database"
    exit 1
fi
echo "DM Trial study_id: $DM_STUDY_ID"

# 1. Ensure "Screening Visit" event definition exists
SCR_EXISTS=$(oc_query "SELECT study_event_definition_id FROM study_event_definition WHERE name = 'Screening Visit' AND study_id = $DM_STUDY_ID AND status_id != 3 LIMIT 1")
if [ -z "$SCR_EXISTS" ]; then
    echo "Adding Screening Visit event definition..."
    oc_query "INSERT INTO study_event_definition (study_id, name, description, repeating, type, status_id, owner_id, date_created, oc_oid, ordinal) VALUES ($DM_STUDY_ID, 'Screening Visit', 'Initial screening visit', false, 'Scheduled', 1, 1, NOW(), 'SE_SCREENING', 1)"
    SCR_EXISTS=$(oc_query "SELECT study_event_definition_id FROM study_event_definition WHERE name = 'Screening Visit' AND study_id = $DM_STUDY_ID AND status_id != 3 LIMIT 1")
fi

# 2. Ensure subjects SS_101, SS_102, SS_103 exist
for LABEL in SS_101 SS_102 SS_103; do
    SUBJ_EXISTS=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = '$LABEL' AND study_id = $DM_STUDY_ID LIMIT 1")
    if [ -z "$SUBJ_EXISTS" ]; then
        echo "Creating subject $LABEL..."
        oc_query "INSERT INTO subject (date_of_birth, gender, status_id, owner_id, date_created) VALUES ('1980-06-15', 'm', 1, 1, NOW())"
        NEW_SUBJ_ID=$(oc_query "SELECT subject_id FROM subject ORDER BY subject_id DESC LIMIT 1")
        oc_query "INSERT INTO study_subject (label, subject_id, study_id, status_id, owner_id, date_created, enrollment_date, oc_oid) VALUES ('$LABEL', $NEW_SUBJ_ID, $DM_STUDY_ID, 1, 1, NOW(), CURRENT_DATE, 'SS_$LABEL')"
    fi
done

# 3. Clean state: Remove any existing events for these subjects
for LABEL in SS_101 SS_102 SS_103; do
    SS_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = '$LABEL' AND study_id = $DM_STUDY_ID LIMIT 1")
    if [ -n "$SS_ID" ]; then
        oc_query "DELETE FROM study_event WHERE study_subject_id = $SS_ID" 2>/dev/null || true
    fi
done
echo "Cleaned pre-existing events for task subjects"

# Record task start time (Unix epoch for anti-gaming)
date +%s > /tmp/task_start_timestamp

# Generate integrity nonce
NONCE=$(generate_result_nonce)
echo "Integrity Nonce: $NONCE"

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

# Record initial audit count
AUDIT_BASELINE=$(get_recent_audit_count 15)
echo "${AUDIT_BASELINE:-0}" > /tmp/audit_baseline_count

take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="