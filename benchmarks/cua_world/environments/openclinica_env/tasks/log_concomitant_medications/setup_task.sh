#!/bin/bash
echo "=== Setting up log_concomitant_medications task ==="

source /workspace/scripts/task_utils.sh

# Record timestamp
date +%s > /tmp/task_start_timestamp

# Get the DM Trial study_id
DM_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' AND status_id != 3 LIMIT 1")
if [ -z "$DM_STUDY_ID" ]; then
    echo "ERROR: Phase II Diabetes Trial not found in database"
    exit 1
fi
echo "DM Trial study_id: $DM_STUDY_ID"

# 1. Ensure Concomitant Medication event definition exists and is fresh
# We delete existing ones to ensure a clean state
EXISTING_CONMED_SED=$(oc_query "SELECT study_event_definition_id FROM study_event_definition WHERE name = 'Concomitant Medication' AND study_id = $DM_STUDY_ID")
if [ -n "$EXISTING_CONMED_SED" ]; then
    for SED_ID in $EXISTING_CONMED_SED; do
        oc_query "DELETE FROM study_event WHERE study_event_definition_id = $SED_ID" 2>/dev/null || true
        oc_query "DELETE FROM study_event_definition WHERE study_event_definition_id = $SED_ID" 2>/dev/null || true
    done
fi

echo "Adding Concomitant Medication event definition to DM Trial..."
# repeating=true (t), type='Unscheduled'
oc_query "INSERT INTO study_event_definition (study_id, name, description, repeating, type, status_id, owner_id, date_created, oc_oid, ordinal) VALUES ($DM_STUDY_ID, 'Concomitant Medication', 'Log of concomitant medications', true, 'Unscheduled', 1, 1, NOW(), 'SE_CONMED', 3)"
echo "Concomitant Medication event definition added"

# 2. Ensure subject DM-104 exists
DM104_SUBJ_ID=$(oc_query "SELECT subject_id FROM subject WHERE unique_identifier = 'DM-104' LIMIT 1")
if [ -z "$DM104_SUBJ_ID" ]; then
    echo "Creating subject record for DM-104..."
    oc_query "INSERT INTO subject (date_of_birth, gender, unique_identifier, status_id, owner_id, date_created) VALUES ('1975-08-12', 'm', 'DM-104', 1, 1, NOW())"
    DM104_SUBJ_ID=$(oc_query "SELECT subject_id FROM subject WHERE unique_identifier = 'DM-104' LIMIT 1")
fi

DM104_SS_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = 'DM-104' AND study_id = $DM_STUDY_ID LIMIT 1")
if [ -z "$DM104_SS_ID" ]; then
    echo "Enrolling DM-104 in DM Trial..."
    oc_query "INSERT INTO study_subject (label, subject_id, study_id, status_id, owner_id, date_created, enrollment_date, oc_oid) VALUES ('DM-104', $DM104_SUBJ_ID, $DM_STUDY_ID, 1, 1, NOW(), NOW(), 'SS_DM104')"
    DM104_SS_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = 'DM-104' AND study_id = $DM_STUDY_ID LIMIT 1")
fi

# 3. Clean up any existing study_events for DM-104 to ensure agent starts from scratch
if [ -n "$DM104_SS_ID" ]; then
    echo "Cleaning up any pre-existing events for DM-104..."
    oc_query "DELETE FROM study_event WHERE study_subject_id = $DM104_SS_ID" 2>/dev/null || true
fi

# 4. Record baseline audit count
AUDIT_BASELINE=$(get_recent_audit_count 15)
echo "${AUDIT_BASELINE:-0}" > /tmp/audit_baseline_count
echo "Audit log baseline after setup: ${AUDIT_BASELINE:-0}"

# 5. Generate result nonce
NONCE=$(generate_result_nonce)
echo "Nonce: $NONCE"

# 6. Ensure Firefox is running and logged in
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

echo "=== log_concomitant_medications setup complete ==="