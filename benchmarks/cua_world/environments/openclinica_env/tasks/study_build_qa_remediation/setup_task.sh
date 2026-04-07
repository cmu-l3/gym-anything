#!/bin/bash
echo "=== Setting up study_build_qa_remediation task ==="

source /workspace/scripts/task_utils.sh

# -------------------------------------------------------------------------
# DB CLEANUP & SEEDING (Seed the "errors" for the agent to fix)
# -------------------------------------------------------------------------

echo "Checking for pre-existing ONC-2025 study..."
ONC_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier='ONC-2025' LIMIT 1" 2>/dev/null)
if [ -n "$ONC_ID" ]; then
    echo "Cleaning up pre-existing ONC-2025..."
    oc_query "DELETE FROM event_definition_crf WHERE study_id=$ONC_ID" 2>/dev/null || true
    oc_query "DELETE FROM study_event_definition WHERE study_id=$ONC_ID" 2>/dev/null || true
    oc_query "DELETE FROM study WHERE study_id=$ONC_ID" 2>/dev/null || true
fi

echo "Creating ONC-2025 study with incorrect Phase I..."
oc_query "INSERT INTO study (name, unique_identifier, phase, status_id, owner_id, date_created, protocol_type, principal_investigator, oc_oid) VALUES ('Oncology Phase II Trial', 'ONC-2025', 'Phase I', 1, 1, NOW(), 'interventional', 'Dr. Smith', 'S_ONC2025')"
ONC_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'ONC-2025' LIMIT 1")

echo "Creating Event Definitions (with Baseline repeating=true and AE type=Scheduled)..."
oc_query "INSERT INTO study_event_definition (study_id, name, repeating, type, status_id, owner_id, date_created, oc_oid, ordinal) VALUES ($ONC_STUDY_ID, 'Screening Visit', false, 'Scheduled', 1, 1, NOW(), 'SE_SCREENING', 1)"
oc_query "INSERT INTO study_event_definition (study_id, name, repeating, type, status_id, owner_id, date_created, oc_oid, ordinal) VALUES ($ONC_STUDY_ID, 'Baseline Visit', true, 'Scheduled', 1, 1, NOW(), 'SE_BASELINE', 2)"
oc_query "INSERT INTO study_event_definition (study_id, name, repeating, type, status_id, owner_id, date_created, oc_oid, ordinal) VALUES ($ONC_STUDY_ID, 'Week 8 Follow-up', false, 'Scheduled', 1, 1, NOW(), 'SE_WEEK8', 3)"
oc_query "INSERT INTO study_event_definition (study_id, name, repeating, type, status_id, owner_id, date_created, oc_oid, ordinal) VALUES ($ONC_STUDY_ID, 'Adverse Event Report', false, 'Scheduled', 1, 1, NOW(), 'SE_AE', 4)"

echo "Ensuring CRFs exist..."
DEMO_EXISTS=$(oc_query "SELECT crf_id FROM crf WHERE name='Demographics' LIMIT 1")
if [ -z "$DEMO_EXISTS" ]; then
    oc_query "INSERT INTO crf (status_id, name, description, owner_id, date_created, oc_oid) VALUES (1, 'Demographics', 'Demographics', 1, NOW(), 'F_DEMOGRAPHICS')"
    DEMO_EXISTS=$(oc_query "SELECT crf_id FROM crf WHERE name='Demographics' LIMIT 1")
    oc_query "INSERT INTO crf_version (crf_id, name, description, status_id, owner_id, date_created, oc_oid) VALUES ($DEMO_EXISTS, 'v1.0', 'v1.0', 1, 1, NOW(), 'F_DEMOGRAPHICS_V10')"
fi

VITALS_EXISTS=$(oc_query "SELECT crf_id FROM crf WHERE name='Vital Signs' LIMIT 1")
if [ -z "$VITALS_EXISTS" ]; then
    oc_query "INSERT INTO crf (status_id, name, description, owner_id, date_created, oc_oid) VALUES (1, 'Vital Signs', 'Vital Signs', 1, NOW(), 'F_VITALSIGNS')"
    VITALS_EXISTS=$(oc_query "SELECT crf_id FROM crf WHERE name='Vital Signs' LIMIT 1")
    oc_query "INSERT INTO crf_version (crf_id, name, description, status_id, owner_id, date_created, oc_oid) VALUES ($VITALS_EXISTS, 'v1.0', 'v1.0', 1, 1, NOW(), 'F_VITALSIGNS_V10')"
fi

echo "Creating incorrect Event-CRF mapping (Demographics -> Week 8)..."
WK8_SED_ID=$(oc_query "SELECT study_event_definition_id FROM study_event_definition WHERE study_id=$ONC_STUDY_ID AND name='Week 8 Follow-up' LIMIT 1")
DEMO_VERSION_ID=$(oc_query "SELECT crf_version_id FROM crf_version WHERE crf_id=$DEMO_EXISTS LIMIT 1")
oc_query "INSERT INTO event_definition_crf (study_event_definition_id, study_id, crf_id, default_version_id, required_crf, double_entry, require_all_text_filled, decision_conditions, status_id, owner_id, date_created) VALUES ($WK8_SED_ID, $ONC_STUDY_ID, $DEMO_EXISTS, $DEMO_VERSION_ID, false, false, false, false, 1, 1, NOW())"

# -------------------------------------------------------------------------
# BROWSER SETUP & LOGGING IN
# -------------------------------------------------------------------------

date +%s > /tmp/task_start_timestamp

# Ensure Firefox running and logged in
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    DISPLAY=:1 firefox 'http://localhost:8080/OpenClinica/MainMenu' > /tmp/firefox_task.log 2>&1 &
    sleep 5
fi

wait_for_window "firefox\|mozilla\|OpenClinica" 30
ensure_logged_in

echo "Switching active study to ONC-2025..."
switch_active_study "ONC-2025"
focus_firefox
sleep 1

# -------------------------------------------------------------------------
# AUDIT LOG & NONCE GENERATION
# -------------------------------------------------------------------------
AUDIT_BASELINE=$(get_recent_audit_count 15)
echo "${AUDIT_BASELINE:-0}" > /tmp/audit_baseline_count
echo "Audit log baseline after setup: ${AUDIT_BASELINE:-0}"

NONCE=$(generate_result_nonce)
echo "Nonce: $NONCE"

take_screenshot /tmp/task_start_screenshot.png

echo "=== setup_task.sh complete ==="