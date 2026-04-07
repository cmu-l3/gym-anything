#!/bin/bash
echo "=== Setting up clinical_data_recovery task ==="

source /workspace/scripts/task_utils.sh

# 1. Resolve Study ID
DM_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' LIMIT 1")
if [ -z "$DM_STUDY_ID" ]; then
    echo "ERROR: Phase II Diabetes Trial (DM-TRIAL-2024) not found"
    exit 1
fi
echo "DM Trial study_id: $DM_STUDY_ID"

# 2. Setup Subject DM-106 (Mark as Removed: status_id = 5)
DM106_EXISTS=$(oc_query "SELECT COUNT(*) FROM study_subject WHERE label = 'DM-106' AND study_id = $DM_STUDY_ID")
if [ "$DM106_EXISTS" = "0" ] || [ -z "$DM106_EXISTS" ]; then
    echo "Creating DM-106 as a removed subject..."
    oc_query "INSERT INTO subject (date_of_birth, gender, status_id, unique_identifier, owner_id, date_created) VALUES ('1985-05-15', 'f', 5, 'UID-DM106', 1, NOW())"
    SUBJ_ID=$(oc_query "SELECT subject_id FROM subject WHERE unique_identifier = 'UID-DM106' LIMIT 1")
    oc_query "INSERT INTO study_subject (label, subject_id, study_id, status_id, enrollment_date, owner_id, date_created) VALUES ('DM-106', $SUBJ_ID, $DM_STUDY_ID, 5, CURRENT_DATE, 1, NOW())"
else
    echo "Marking existing DM-106 as removed..."
    oc_query "UPDATE study_subject SET status_id = 5 WHERE label = 'DM-106' AND study_id = $DM_STUDY_ID"
fi

# 3. Setup DM-102's Week 4 Follow-up Event (Mark as Removed: status_id = 5)
DM102_SS_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = 'DM-102' AND study_id = $DM_STUDY_ID LIMIT 1")

if [ -z "$DM102_SS_ID" ]; then
    echo "WARNING: DM-102 not found, skipping event setup..."
else
    # Ensure event definition exists
    WEEK4_SED_ID=$(oc_query "SELECT study_event_definition_id FROM study_event_definition WHERE name = 'Week 4 Follow-up' AND study_id = $DM_STUDY_ID LIMIT 1")
    if [ -z "$WEEK4_SED_ID" ]; then
        echo "Creating Week 4 Follow-up definition..."
        oc_query "INSERT INTO study_event_definition (study_id, name, repeating, type, status_id, owner_id, date_created) VALUES ($DM_STUDY_ID, 'Week 4 Follow-up', true, 'Scheduled', 1, 1, NOW())"
        WEEK4_SED_ID=$(oc_query "SELECT study_event_definition_id FROM study_event_definition WHERE name = 'Week 4 Follow-up' AND study_id = $DM_STUDY_ID LIMIT 1")
    fi
    
    # Ensure event exists and is removed
    EVENT_ID=$(oc_query "SELECT study_event_id FROM study_event WHERE study_subject_id = $DM102_SS_ID AND study_event_definition_id = $WEEK4_SED_ID LIMIT 1")
    if [ -z "$EVENT_ID" ]; then
        echo "Creating removed event for DM-102..."
        oc_query "INSERT INTO study_event (study_subject_id, study_event_definition_id, start_date, status_id, subject_event_status_id, owner_id, date_created, sample_ordinal) VALUES ($DM102_SS_ID, $WEEK4_SED_ID, CURRENT_DATE, 5, 1, 1, NOW(), 1)"
    else
        echo "Marking existing DM-102 event as removed..."
        oc_query "UPDATE study_event SET status_id = 5 WHERE study_event_id = $EVENT_ID"
    fi
fi

# 4. Save baselines for anti-gaming checks
AUDIT_BASELINE=$(oc_query "SELECT COUNT(*) FROM audit_log_event")
echo "${AUDIT_BASELINE:-0}" > /tmp/audit_baseline_count
echo "Audit baseline: ${AUDIT_BASELINE:-0}"

# 5. Start browser & login
date +%s > /tmp/task_start_timestamp
if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox 'http://localhost:8080/OpenClinica/MainMenu' > /tmp/firefox_task.log 2>&1 &
    sleep 5
fi

wait_for_window "firefox\|mozilla\|OpenClinica" 30
ensure_logged_in
switch_active_study "DM-TRIAL-2024"
focus_firefox
sleep 1

# 6. Final setup confirmation
NONCE=$(python3 -c "import secrets; print(secrets.token_hex(16))")
echo "$NONCE" > /tmp/result_nonce
take_screenshot /tmp/task_start_screenshot.png

echo "=== clinical_data_recovery setup complete ==="