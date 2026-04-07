#!/bin/bash
echo "=== Setting up remediate_misallocated_clinical_data task ==="

source /workspace/scripts/task_utils.sh

# Record timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# Get the DM Trial study_id
DM_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' AND status_id != 3 LIMIT 1")
if [ -z "$DM_STUDY_ID" ]; then
    echo "ERROR: Phase II Diabetes Trial not found in database"
    exit 1
fi
echo "DM Trial study_id: $DM_STUDY_ID"

# 1. Ensure 'Week 4 Follow-up' event definition exists
WEEK4_EXISTS=$(oc_query "SELECT COUNT(*) FROM study_event_definition WHERE study_id = $DM_STUDY_ID AND name = 'Week 4 Follow-up' AND status_id != 3")
if [ "$WEEK4_EXISTS" = "0" ] || [ -z "$WEEK4_EXISTS" ]; then
    echo "Adding Week 4 Follow-up event definition..."
    oc_query "INSERT INTO study_event_definition (study_id, name, description, repeating, type, status_id, owner_id, date_created, oc_oid, ordinal) VALUES ($DM_STUDY_ID, 'Week 4 Follow-up', 'Follow-up visit', false, 'Scheduled', 1, 1, NOW(), 'SE_DM_WEEK4', 2)"
fi
WEEK4_SED_ID=$(oc_query "SELECT study_event_definition_id FROM study_event_definition WHERE name = 'Week 4 Follow-up' AND study_id = $DM_STUDY_ID AND status_id != 3 LIMIT 1")

# 2. Ensure subjects DM-102 and DM-103 exist
for SUBJ_LABEL in DM-102 DM-103; do
    SS_CHECK=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = '$SUBJ_LABEL' AND study_id = $DM_STUDY_ID LIMIT 1")
    if [ -z "$SS_CHECK" ]; then
        echo "WARNING: Subject $SUBJ_LABEL not found. Inserting baseline subject..."
        # Simplified insertion fallback if baseline is missing
        SUBJ_ID=$(oc_query "INSERT INTO subject (date_of_birth, gender, status_id, owner_id, date_created) VALUES ('1970-01-01', 'm', 1, 1, NOW()) RETURNING subject_id")
        oc_query "INSERT INTO study_subject (label, subject_id, study_id, status_id, owner_id, date_created, enrollment_date) VALUES ('$SUBJ_LABEL', $SUBJ_ID, $DM_STUDY_ID, 1, 1, NOW(), NOW())"
    fi
done

DM102_SS_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = 'DM-102' AND study_id = $DM_STUDY_ID LIMIT 1")
DM103_SS_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = 'DM-103' AND study_id = $DM_STUDY_ID LIMIT 1")

# 3. Clean up any existing Week 4 events for BOTH subjects to establish clean state
for SS_ID in $DM102_SS_ID $DM103_SS_ID; do
    EVENTS=$(oc_query "SELECT study_event_id FROM study_event WHERE study_subject_id = $SS_ID AND study_event_definition_id = $WEEK4_SED_ID")
    for EV_ID in $EVENTS; do
        oc_query "DELETE FROM item_data WHERE event_crf_id IN (SELECT event_crf_id FROM event_crf WHERE study_event_id = $EV_ID)" 2>/dev/null || true
        oc_query "DELETE FROM event_crf WHERE study_event_id = $EV_ID" 2>/dev/null || true
        oc_query "DELETE FROM study_event WHERE study_event_id = $EV_ID" 2>/dev/null || true
    done
done

# 4. Inject the simulated error: Schedule Week 4 for DM-103
echo "Simulating error: Scheduling Week 4 for DM-103..."
oc_query "INSERT INTO study_event (study_subject_id, study_event_definition_id, start_date, location, status_id, owner_id, date_created, sample_ordinal, subject_event_status_id) VALUES ($DM103_SS_ID, $WEEK4_SED_ID, '2024-03-09', 'Mistake Clinic', 1, 1, NOW(), 1, 1)"

# 5. Provide CRF template just in case the system needs it
if [ -f "/workspace/data/sample_crf.xls" ]; then
    cp /workspace/data/sample_crf.xls /home/ga/vital_signs_crf.xls
    chown ga:ga /home/ga/vital_signs_crf.xls
    chmod 644 /home/ga/vital_signs_crf.xls
fi

# 6. Set up browser
if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox 'http://localhost:8080/OpenClinica/MainMenu' > /tmp/firefox_task.log 2>&1 &
    sleep 5
fi

wait_for_window "firefox\|mozilla\|OpenClinica" 30
ensure_logged_in
switch_active_study "DM-TRIAL-2024"
focus_firefox
sleep 1

# 7. Record baselines and nonces
AUDIT_BASELINE=$(get_recent_audit_count 15)
echo "${AUDIT_BASELINE:-0}" > /tmp/audit_baseline_count
echo "Audit log baseline after setup: ${AUDIT_BASELINE:-0}"

NONCE=$(generate_result_nonce)
echo "Nonce: $NONCE"

# Final initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup complete ==="