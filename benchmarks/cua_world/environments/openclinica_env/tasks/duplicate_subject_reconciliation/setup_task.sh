#!/bin/bash
echo "=== Setting up duplicate_subject_reconciliation task ==="

source /workspace/scripts/task_utils.sh

# Get the DM Trial study_id
DM_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' AND status_id != 3 LIMIT 1")
if [ -z "$DM_STUDY_ID" ]; then
    echo "ERROR: Phase II Diabetes Trial not found in database"
    exit 1
fi
echo "DM Trial study_id: $DM_STUDY_ID"

# 1. Add event definitions if they don't exist
BASELINE_EXISTS=$(oc_query "SELECT COUNT(*) FROM study_event_definition WHERE study_id = $DM_STUDY_ID AND name = 'Baseline Assessment' AND status_id != 3")
if [ "$BASELINE_EXISTS" = "0" ] || [ -z "$BASELINE_EXISTS" ]; then
    oc_query "INSERT INTO study_event_definition (study_id, name, description, repeating, type, status_id, owner_id, date_created, oc_oid, ordinal) VALUES ($DM_STUDY_ID, 'Baseline Assessment', 'Baseline', false, 'Scheduled', 1, 1, NOW(), 'SE_DM_BASE', 1)"
fi

WEEK4_EXISTS=$(oc_query "SELECT COUNT(*) FROM study_event_definition WHERE study_id = $DM_STUDY_ID AND name = 'Week 4 Follow-up' AND status_id != 3")
if [ "$WEEK4_EXISTS" = "0" ] || [ -z "$WEEK4_EXISTS" ]; then
    oc_query "INSERT INTO study_event_definition (study_id, name, description, repeating, type, status_id, owner_id, date_created, oc_oid, ordinal) VALUES ($DM_STUDY_ID, 'Week 4 Follow-up', 'Week 4', false, 'Scheduled', 1, 1, NOW(), 'SE_DM_WK4', 2)"
fi

# 2. Clean up subjects DM-105 and DM-106 to start fresh
for SUBJ in DM-105 DM-106; do
    SS_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = '$SUBJ' AND study_id = $DM_STUDY_ID LIMIT 1")
    if [ -n "$SS_ID" ]; then
        oc_query "DELETE FROM study_event WHERE study_subject_id = $SS_ID" 2>/dev/null || true
        SUBJ_ID=$(oc_query "SELECT subject_id FROM study_subject WHERE study_subject_id = $SS_ID LIMIT 1")
        oc_query "DELETE FROM study_subject WHERE study_subject_id = $SS_ID" 2>/dev/null || true
        if [ -n "$SUBJ_ID" ]; then
            oc_query "DELETE FROM subject WHERE subject_id = $SUBJ_ID" 2>/dev/null || true
        fi
    fi
done

# 3. Create Subject DM-105
oc_query "INSERT INTO subject (date_of_birth, gender, status_id, owner_id, date_created, unique_identifier) VALUES ('1980-05-15', 'm', 1, 1, NOW(), 'SUBJ_105')"
SUBJ_105_ID=$(oc_query "SELECT subject_id FROM subject WHERE unique_identifier = 'SUBJ_105' ORDER BY subject_id DESC LIMIT 1")
oc_query "INSERT INTO study_subject (label, subject_id, study_id, status_id, enrollment_date, owner_id, date_created, oc_oid) VALUES ('DM-105', $SUBJ_105_ID, $DM_STUDY_ID, 1, NOW(), 1, NOW(), 'SS_DM105')"
SS_105_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = 'DM-105' AND study_id = $DM_STUDY_ID LIMIT 1")

# 4. Create Subject DM-106
oc_query "INSERT INTO subject (date_of_birth, gender, status_id, owner_id, date_created, unique_identifier) VALUES ('1980-05-15', 'm', 1, 1, NOW(), 'SUBJ_106')"
SUBJ_106_ID=$(oc_query "SELECT subject_id FROM subject WHERE unique_identifier = 'SUBJ_106' ORDER BY subject_id DESC LIMIT 1")
oc_query "INSERT INTO study_subject (label, subject_id, study_id, status_id, enrollment_date, owner_id, date_created, oc_oid) VALUES ('DM-106', $SUBJ_106_ID, $DM_STUDY_ID, 1, NOW(), 1, NOW(), 'SS_DM106')"
SS_106_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = 'DM-106' AND study_id = $DM_STUDY_ID LIMIT 1")

# 5. Schedule Baseline for DM-105
BASE_SED_ID=$(oc_query "SELECT study_event_definition_id FROM study_event_definition WHERE name = 'Baseline Assessment' AND study_id = $DM_STUDY_ID LIMIT 1")
oc_query "INSERT INTO study_event (study_subject_id, study_event_definition_id, start_date, status_id, owner_id, date_created, sample_ordinal) VALUES ($SS_105_ID, $BASE_SED_ID, '2024-02-01', 1, 1, NOW(), 1)"

# 6. Schedule Week 4 Follow-up for DM-106
WK4_SED_ID=$(oc_query "SELECT study_event_definition_id FROM study_event_definition WHERE name = 'Week 4 Follow-up' AND study_id = $DM_STUDY_ID LIMIT 1")
oc_query "INSERT INTO study_event (study_subject_id, study_event_definition_id, start_date, status_id, owner_id, date_created, sample_ordinal) VALUES ($SS_106_ID, $WK4_SED_ID, '2024-03-01', 1, 1, NOW(), 1)"

# 7. Provide the CRF Template File
mkdir -p /home/ga/Desktop
if [ -f "/workspace/data/sample_crf.xls" ]; then
    cp /workspace/data/sample_crf.xls /home/ga/Desktop/vital_signs_crf.xls
    chown ga:ga /home/ga/Desktop/vital_signs_crf.xls
    chmod 644 /home/ga/Desktop/vital_signs_crf.xls
    echo "Provided CRF template at /home/ga/Desktop/vital_signs_crf.xls"
fi

# 8. Record initial state and baselines
echo "$DM_STUDY_ID" > /tmp/dm_study_id
echo "$SS_105_ID" > /tmp/dm105_ss_id
echo "$SS_106_ID" > /tmp/dm106_ss_id
echo "$WK4_SED_ID" > /tmp/wk4_sed_id

date +%s > /tmp/task_start_timestamp
AUDIT_BASELINE=$(get_recent_audit_count 15)
echo "${AUDIT_BASELINE:-0}" > /tmp/audit_baseline_count
NONCE=$(generate_result_nonce)
echo "Nonce: $NONCE"

# 9. Ensure browser is ready
if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox 'http://localhost:8080/OpenClinica/MainMenu' > /tmp/firefox_task.log 2>&1 &
    sleep 5
fi

wait_for_window "firefox\|mozilla\|OpenClinica" 30
ensure_logged_in
switch_active_study "DM-TRIAL-2024"
focus_firefox

take_screenshot /tmp/task_start_screenshot.png
echo "=== Setup complete ==="