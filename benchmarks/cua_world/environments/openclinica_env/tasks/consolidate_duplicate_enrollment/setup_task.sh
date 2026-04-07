#!/bin/bash
echo "=== Setting up consolidate_duplicate_enrollment task ==="

source /workspace/scripts/task_utils.sh

# 1. Resolve DM Trial Study ID
DM_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' AND status_id != 3 LIMIT 1")
if [ -z "$DM_STUDY_ID" ]; then
    echo "ERROR: Phase II Diabetes Trial not found in database"
    exit 1
fi
echo "DM Trial study_id: $DM_STUDY_ID"

# 2. Ensure Baseline Assessment Event Def Exists
BASELINE_EXISTS=$(oc_query "SELECT COUNT(*) FROM study_event_definition WHERE study_id = $DM_STUDY_ID AND name = 'Baseline Assessment' AND status_id != 3")
if [ "$BASELINE_EXISTS" = "0" ] || [ -z "$BASELINE_EXISTS" ]; then
    oc_query "INSERT INTO study_event_definition (study_id, name, description, repeating, type, status_id, owner_id, date_created, oc_oid, ordinal) VALUES ($DM_STUDY_ID, 'Baseline Assessment', 'Initial baseline study visit', false, 'Scheduled', 1, 1, NOW(), 'SE_DM_BASELINE', 1)"
fi
BASELINE_SED_ID=$(oc_query "SELECT study_event_definition_id FROM study_event_definition WHERE name = 'Baseline Assessment' AND study_id = $DM_STUDY_ID AND status_id != 3 LIMIT 1")

# 3. Setup DM-204 (Correct demographics, missing Secondary ID and no events scheduled)
SUBJ_204_ID=$(oc_query "SELECT subject_id FROM subject WHERE unique_identifier = 'SUBJ-204' LIMIT 1")
if [ -z "$SUBJ_204_ID" ]; then
    oc_query "INSERT INTO subject (status_id, owner_id, date_created, date_of_birth, gender, unique_identifier) VALUES (1, 1, NOW(), '1975-08-14', 'f', 'SUBJ-204')"
    SUBJ_204_ID=$(oc_query "SELECT subject_id FROM subject WHERE unique_identifier = 'SUBJ-204' LIMIT 1")
fi

DM204_SS_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = 'DM-204' AND study_id = $DM_STUDY_ID LIMIT 1")
if [ -z "$DM204_SS_ID" ]; then
    oc_query "INSERT INTO study_subject (label, secondary_label, subject_id, study_id, status_id, owner_id, date_created, enrollment_date, oc_oid) VALUES ('DM-204', '', $SUBJ_204_ID, $DM_STUDY_ID, 1, 1, NOW(), NOW(), 'SS_DM_204')"
    DM204_SS_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = 'DM-204' AND study_id = $DM_STUDY_ID LIMIT 1")
fi

# Reset state for DM-204
oc_query "UPDATE study_subject SET status_id = 1, secondary_label = '' WHERE study_subject_id = $DM204_SS_ID"
oc_query "DELETE FROM study_event WHERE study_subject_id = $DM204_SS_ID"

# 4. Setup DM-205 (Duplicate with bad DOB but with a scheduled event)
SUBJ_205_ID=$(oc_query "SELECT subject_id FROM subject WHERE unique_identifier = 'SUBJ-205' LIMIT 1")
if [ -z "$SUBJ_205_ID" ]; then
    oc_query "INSERT INTO subject (status_id, owner_id, date_created, date_of_birth, gender, unique_identifier) VALUES (1, 1, NOW(), '1976-08-14', 'f', 'SUBJ-205')"
    SUBJ_205_ID=$(oc_query "SELECT subject_id FROM subject WHERE unique_identifier = 'SUBJ-205' LIMIT 1")
fi

DM205_SS_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = 'DM-205' AND study_id = $DM_STUDY_ID LIMIT 1")
if [ -z "$DM205_SS_ID" ]; then
    oc_query "INSERT INTO study_subject (label, subject_id, study_id, status_id, owner_id, date_created, enrollment_date, oc_oid) VALUES ('DM-205', $SUBJ_205_ID, $DM_STUDY_ID, 1, 1, NOW(), NOW(), 'SS_DM_205')"
    DM205_SS_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = 'DM-205' AND study_id = $DM_STUDY_ID LIMIT 1")
fi

# Reset state for DM-205
oc_query "UPDATE study_subject SET status_id = 1 WHERE study_subject_id = $DM205_SS_ID"
oc_query "DELETE FROM study_event WHERE study_subject_id = $DM205_SS_ID"
# Seed the duplicate with the event we actually want the agent to move over to DM-204
oc_query "INSERT INTO study_event (study_subject_id, study_event_definition_id, start_date, status_id, owner_id, date_created, sample_ordinal) VALUES ($DM205_SS_ID, $BASELINE_SED_ID, '2024-05-15', 1, 1, NOW(), 1)"

# 5. Open Application
if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox 'http://localhost:8080/OpenClinica/MainMenu' > /tmp/firefox_task.log 2>&1 &
    sleep 5
fi

wait_for_window "firefox\|mozilla\|OpenClinica" 30
ensure_logged_in
switch_active_study "DM-TRIAL-2024"
focus_firefox
sleep 1

# 6. Record State / Nonce for verification integrity
AUDIT_BASELINE=$(docker exec oc-postgres psql -U clinica openclinica -tAc "SELECT COUNT(*) FROM audit_log_event" 2>/dev/null || echo "0")
echo "${AUDIT_BASELINE:-0}" > /tmp/audit_baseline_count
date +%s > /tmp/task_start_timestamp

NONCE=$RANDOM$RANDOM
echo "$NONCE" > /tmp/result_nonce

take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup complete ==="