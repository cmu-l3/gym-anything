#!/bin/bash
echo "=== Setting up reconcile_study_event_statuses task ==="

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

# ---------------------------------------------------------------
# Add Baseline Assessment event definition if it doesn't exist
# ---------------------------------------------------------------
BASELINE_SED_ID=$(oc_query "SELECT study_event_definition_id FROM study_event_definition WHERE study_id = $DM_STUDY_ID AND name = 'Baseline Assessment' AND status_id != 3 LIMIT 1")
if [ -z "$BASELINE_SED_ID" ]; then
    echo "Adding Baseline Assessment event definition to DM Trial..."
    oc_query "INSERT INTO study_event_definition (study_id, name, description, repeating, type, status_id, owner_id, date_created, oc_oid, ordinal) VALUES ($DM_STUDY_ID, 'Baseline Assessment', 'Initial baseline study visit', false, 'Scheduled', 1, 1, NOW(), 'SE_DM_BASELINE', 1)"
    BASELINE_SED_ID=$(oc_query "SELECT study_event_definition_id FROM study_event_definition WHERE study_id = $DM_STUDY_ID AND name = 'Baseline Assessment' AND status_id != 3 LIMIT 1")
fi
echo "Baseline Assessment SED ID: $BASELINE_SED_ID"

# ---------------------------------------------------------------
# Seed Subjects and their Event Statuses
# ---------------------------------------------------------------
# Subject 101, 102, 103, 105 -> Status 3 (Data Entry Started)
# Subject 104 -> Status 4 (Completed)
for i in 1 2 3 4 5; do
    LABEL="DM-10${i}"
    
    # Ensure subject exists
    SUBJ_ID=$(oc_query "SELECT subject_id FROM subject WHERE unique_identifier = '$LABEL' LIMIT 1")
    if [ -z "$SUBJ_ID" ]; then
        oc_query "INSERT INTO subject (date_of_birth, gender, unique_identifier, status_id, owner_id, date_created) VALUES ('1970-01-01', 'm', '$LABEL', 1, 1, NOW())"
        SUBJ_ID=$(oc_query "SELECT subject_id FROM subject WHERE unique_identifier = '$LABEL' LIMIT 1")
    fi
    
    # Ensure study_subject exists
    SS_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = '$LABEL' AND study_id = $DM_STUDY_ID LIMIT 1")
    if [ -z "$SS_ID" ]; then
        oc_query "INSERT INTO study_subject (label, subject_id, study_id, status_id, owner_id, date_created, enrollment_date) VALUES ('$LABEL', $SUBJ_ID, $DM_STUDY_ID, 1, 1, NOW(), NOW())"
        SS_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = '$LABEL' AND study_id = $DM_STUDY_ID LIMIT 1")
    fi
    
    # Ensure study_event exists
    SE_ID=$(oc_query "SELECT study_event_id FROM study_event WHERE study_subject_id = $SS_ID AND study_event_definition_id = $BASELINE_SED_ID LIMIT 1")
    if [ -z "$SE_ID" ]; then
        oc_query "INSERT INTO study_event (study_subject_id, study_event_definition_id, status_id, owner_id, date_created, subject_event_status_id, sample_ordinal, start_date) VALUES ($SS_ID, $BASELINE_SED_ID, 1, 1, NOW(), 3, 1, NOW())"
        SE_ID=$(oc_query "SELECT study_event_id FROM study_event WHERE study_subject_id = $SS_ID AND study_event_definition_id = $BASELINE_SED_ID LIMIT 1")
    fi
    
    # Set the target subject_event_status_id for the task condition
    TARGET_STATUS=3
    if [ "$i" = "4" ]; then
        TARGET_STATUS=4
    fi
    
    oc_query "UPDATE study_event SET subject_event_status_id = $TARGET_STATUS WHERE study_event_id = $SE_ID"
    echo "Configured $LABEL with Baseline Assessment status_id = $TARGET_STATUS"
done

# ---------------------------------------------------------------
# Record initial baseline data
# ---------------------------------------------------------------
AUDIT_BASELINE=$(get_recent_audit_count 15)
echo "${AUDIT_BASELINE:-0}" > /tmp/audit_baseline_count
echo "Audit log baseline after setup: ${AUDIT_BASELINE:-0}"

NONCE=$(generate_result_nonce)
echo "Nonce: $NONCE"

# ---------------------------------------------------------------
# Start Firefox and ensure active session
# ---------------------------------------------------------------
if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox 'http://localhost:8080/OpenClinica/MainMenu' > /tmp/firefox_task.log 2>&1 &
    sleep 5
fi

wait_for_window "firefox\|mozilla\|OpenClinica" 30
ensure_logged_in
switch_active_study "DM-TRIAL-2024"
focus_firefox
sleep 1

# Take a screenshot indicating the starting UI state
take_screenshot /tmp/task_start_screenshot.png

echo "=== reconcile_study_event_statuses setup complete ==="