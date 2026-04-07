#!/bin/bash
echo "=== Setting up administrative_data_invalidation task ==="

source /workspace/scripts/task_utils.sh

# Get the DM Trial study_id
DM_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' AND status_id != 3 LIMIT 1")
if [ -z "$DM_STUDY_ID" ]; then
    echo "ERROR: Phase II Diabetes Trial not found in database"
    exit 1
fi

# Ensure subjects exist
for label in DM-101 DM-102 DM-104; do
    EXISTS=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = '$label' AND study_id = $DM_STUDY_ID LIMIT 1")
    if [ -z "$EXISTS" ]; then
        SUBJ_ID=$(oc_query "INSERT INTO subject (date_of_birth, gender, status_id, owner_id, date_created, unique_identifier) VALUES ('1980-01-01', 'm', 1, 1, NOW(), '$label-UID') RETURNING subject_id")
        oc_query "INSERT INTO study_subject (label, subject_id, study_id, status_id, owner_id, date_created, enrollment_date, oc_oid) VALUES ('$label', $SUBJ_ID, $DM_STUDY_ID, 1, 1, NOW(), NOW(), 'SS_$label')"
    fi
done

# Ensure SEDs exist
SED_BASELINE=$(oc_query "SELECT study_event_definition_id FROM study_event_definition WHERE name = 'Baseline Assessment' AND study_id = $DM_STUDY_ID LIMIT 1")
if [ -z "$SED_BASELINE" ]; then
    SED_BASELINE=$(oc_query "INSERT INTO study_event_definition (study_id, name, description, repeating, type, status_id, owner_id, date_created, oc_oid, ordinal) VALUES ($DM_STUDY_ID, 'Baseline Assessment', 'Baseline', false, 'Scheduled', 1, 1, NOW(), 'SE_BASELINE', 1) RETURNING study_event_definition_id")
fi

SED_WEEK8=$(oc_query "SELECT study_event_definition_id FROM study_event_definition WHERE name = 'Week 8 Follow-up' AND study_id = $DM_STUDY_ID LIMIT 1")
if [ -z "$SED_WEEK8" ]; then
    SED_WEEK8=$(oc_query "INSERT INTO study_event_definition (study_id, name, description, repeating, type, status_id, owner_id, date_created, oc_oid, ordinal) VALUES ($DM_STUDY_ID, 'Week 8 Follow-up', 'Week 8', false, 'Scheduled', 1, 1, NOW(), 'SE_WEEK8', 2) RETURNING study_event_definition_id")
fi

# Ensure CRFs exist
CRF_PREG_ID=$(oc_query "SELECT crf_id FROM crf WHERE name = 'Pregnancy Status' LIMIT 1")
if [ -z "$CRF_PREG_ID" ]; then
    CRF_PREG_ID=$(oc_query "INSERT INTO crf (status_id, name, description, owner_id, date_created, oc_oid, source_study_id) VALUES (1, 'Pregnancy Status', 'Pregnancy Status', 1, NOW(), 'F_PREGNANCY', $DM_STUDY_ID) RETURNING crf_id")
    CRF_PREG_VID=$(oc_query "INSERT INTO crf_version (crf_id, name, description, status_id, owner_id, date_created, oc_oid) VALUES ($CRF_PREG_ID, 'v1.0', 'v1.0', 1, 1, NOW(), 'F_PREGNANCY_V10') RETURNING crf_version_id")
else
    CRF_PREG_VID=$(oc_query "SELECT crf_version_id FROM crf_version WHERE crf_id = $CRF_PREG_ID LIMIT 1")
fi

CRF_VITAL_ID=$(oc_query "SELECT crf_id FROM crf WHERE name = 'Vital Signs' LIMIT 1")
if [ -z "$CRF_VITAL_ID" ]; then
    CRF_VITAL_ID=$(oc_query "INSERT INTO crf (status_id, name, description, owner_id, date_created, oc_oid, source_study_id) VALUES (1, 'Vital Signs', 'Vital Signs', 1, NOW(), 'F_VITALSIGNS', $DM_STUDY_ID) RETURNING crf_id")
    CRF_VITAL_VID=$(oc_query "INSERT INTO crf_version (crf_id, name, description, status_id, owner_id, date_created, oc_oid) VALUES ($CRF_VITAL_ID, 'v1.0', 'v1.0', 1, 1, NOW(), 'F_VITALSIGNS_V10') RETURNING crf_version_id")
else
    CRF_VITAL_VID=$(oc_query "SELECT crf_version_id FROM crf_version WHERE crf_id = $CRF_VITAL_ID LIMIT 1")
fi

# Link CRFs to SEDs
oc_query "INSERT INTO event_definition_crf (study_event_definition_id, study_id, crf_id, required_crf, double_entry, require_all_text_filled, decision_conditions, null_values, status_id, owner_id, date_created, default_version_id) SELECT $SED_BASELINE, $DM_STUDY_ID, $CRF_PREG_ID, false, false, false, false, false, 1, 1, NOW(), $CRF_PREG_VID WHERE NOT EXISTS (SELECT 1 FROM event_definition_crf WHERE study_event_definition_id=$SED_BASELINE AND crf_id=$CRF_PREG_ID)" 2>/dev/null || true

oc_query "INSERT INTO event_definition_crf (study_event_definition_id, study_id, crf_id, required_crf, double_entry, require_all_text_filled, decision_conditions, null_values, status_id, owner_id, date_created, default_version_id) SELECT $SED_BASELINE, $DM_STUDY_ID, $CRF_VITAL_ID, false, false, false, false, false, 1, 1, NOW(), $CRF_VITAL_VID WHERE NOT EXISTS (SELECT 1 FROM event_definition_crf WHERE study_event_definition_id=$SED_BASELINE AND crf_id=$CRF_VITAL_ID)" 2>/dev/null || true

# Clean up existing events for these 3 subjects to start clean
for label in DM-101 DM-102 DM-104; do
    SS_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = '$label' AND study_id = $DM_STUDY_ID LIMIT 1")
    if [ -n "$SS_ID" ]; then
        oc_query "DELETE FROM event_crf WHERE study_event_id IN (SELECT study_event_id FROM study_event WHERE study_subject_id = $SS_ID)" 2>/dev/null || true
        oc_query "DELETE FROM study_event WHERE study_subject_id = $SS_ID" 2>/dev/null || true
    fi
done

# Create events and CRFs for DM-102 (Pregnancy CRF to remove, Vitals CRF to leave intact)
SS_DM102=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = 'DM-102' AND study_id = $DM_STUDY_ID LIMIT 1")
SE_DM102=$(oc_query "INSERT INTO study_event (study_subject_id, study_event_definition_id, subject_event_status_id, status_id, owner_id, date_created, start_date, sample_ordinal) VALUES ($SS_DM102, $SED_BASELINE, 4, 1, 1, NOW(), NOW(), 1) RETURNING study_event_id")
oc_query "INSERT INTO event_crf (study_event_id, crf_version_id, status_id, owner_id, date_created, date_interviewed) VALUES ($SE_DM102, $CRF_PREG_VID, 2, 1, NOW(), NOW())"
oc_query "INSERT INTO event_crf (study_event_id, crf_version_id, status_id, owner_id, date_created, date_interviewed) VALUES ($SE_DM102, $CRF_VITAL_VID, 2, 1, NOW(), NOW())"

# Create events for DM-104 (Event to remove)
SS_DM104=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = 'DM-104' AND study_id = $DM_STUDY_ID LIMIT 1")
SE_DM104=$(oc_query "INSERT INTO study_event (study_subject_id, study_event_definition_id, subject_event_status_id, status_id, owner_id, date_created, start_date, sample_ordinal) VALUES ($SS_DM104, $SED_WEEK8, 1, 1, 1, NOW(), NOW(), 1) RETURNING study_event_id")

# Create events and CRFs for DM-101 (Vitals CRF to restore)
SS_DM101=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = 'DM-101' AND study_id = $DM_STUDY_ID LIMIT 1")
SE_DM101=$(oc_query "INSERT INTO study_event (study_subject_id, study_event_definition_id, subject_event_status_id, status_id, owner_id, date_created, start_date, sample_ordinal) VALUES ($SS_DM101, $SED_BASELINE, 4, 1, 1, NOW(), NOW(), 1) RETURNING study_event_id")
# Status_id = 5 (Removed)
oc_query "INSERT INTO event_crf (study_event_id, crf_version_id, status_id, owner_id, date_created, date_interviewed) VALUES ($SE_DM101, $CRF_VITAL_VID, 5, 1, NOW(), NOW())"

# UI Setup & Integrity Elements
date +%s > /tmp/task_start_time.txt
AUDIT_BASELINE=$(get_recent_audit_count 15)
echo "${AUDIT_BASELINE:-0}" > /tmp/audit_baseline_count

NONCE=$(generate_result_nonce)
echo "Nonce: $NONCE"

if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox 'http://localhost:8080/OpenClinica/MainMenu' > /tmp/firefox_task.log 2>&1 &
    sleep 5
fi

wait_for_window "firefox\|mozilla\|OpenClinica" 30
ensure_logged_in
switch_active_study "DM-TRIAL-2024"
focus_firefox
sleep 1

take_screenshot /tmp/task_initial_state.png

echo "=== Setup complete ==="