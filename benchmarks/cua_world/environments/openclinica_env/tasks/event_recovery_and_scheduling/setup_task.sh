#!/bin/bash
echo "=== Setting up event_recovery_and_scheduling task ==="

source /workspace/scripts/task_utils.sh

# 1. Get DM Trial study_id
DM_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' AND status_id != 3 LIMIT 1")
if [ -z "$DM_STUDY_ID" ]; then
    echo "ERROR: Phase II Diabetes Trial not found in database"
    exit 1
fi
echo "DM Trial study_id: $DM_STUDY_ID"

# 2. Ensure Month 3 Follow-up and Month 6 Follow-up event definitions exist
for MONTH in 3 6; do
    EVENT_NAME="Month $MONTH Follow-up"
    EXISTS=$(oc_query "SELECT COUNT(*) FROM study_event_definition WHERE study_id = $DM_STUDY_ID AND name = '$EVENT_NAME' AND status_id != 3")
    if [ "$EXISTS" = "0" ] || [ -z "$EXISTS" ]; then
        echo "Adding $EVENT_NAME event definition..."
        oc_query "INSERT INTO study_event_definition (study_id, name, description, repeating, type, status_id, owner_id, date_created, oc_oid, ordinal) VALUES ($DM_STUDY_ID, '$EVENT_NAME', 'Follow-up visit at month $MONTH', false, 'Scheduled', 1, 1, NOW(), 'SE_DM_M${MONTH}', $MONTH)"
    fi
done

M3_SED_ID=$(oc_query "SELECT study_event_definition_id FROM study_event_definition WHERE name = 'Month 3 Follow-up' AND study_id = $DM_STUDY_ID AND status_id != 3 LIMIT 1")
M6_SED_ID=$(oc_query "SELECT study_event_definition_id FROM study_event_definition WHERE name = 'Month 6 Follow-up' AND study_id = $DM_STUDY_ID AND status_id != 3 LIMIT 1")

# 3. Ensure DM-105 exists
DM105_SS_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = 'DM-105' AND study_id = $DM_STUDY_ID LIMIT 1")
if [ -z "$DM105_SS_ID" ]; then
    echo "Creating DM-105..."
    # Create subject
    oc_query "INSERT INTO subject (date_of_birth, gender, status_id, owner_id, date_created, unique_identifier) VALUES ('1982-10-14', 'f', 1, 1, NOW(), 'DM-105-UID')"
    SUBJ_ID=$(oc_query "SELECT subject_id FROM subject WHERE unique_identifier = 'DM-105-UID' ORDER BY subject_id DESC LIMIT 1")
    # Create study_subject
    oc_query "INSERT INTO study_subject (label, subject_id, study_id, status_id, enrollment_date, owner_id, date_created, oc_oid) VALUES ('DM-105', $SUBJ_ID, $DM_STUDY_ID, 1, NOW(), 1, NOW(), 'SS_DM105')"
    DM105_SS_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = 'DM-105' AND study_id = $DM_STUDY_ID LIMIT 1")
fi

# Ensure DM-105 is active
oc_query "UPDATE study_subject SET status_id = 1 WHERE study_subject_id = $DM105_SS_ID"

# 4. Set up Month 3 event as "Removed" (status_id = 5)
M3_EVENT_ID=$(oc_query "SELECT study_event_id FROM study_event WHERE study_subject_id = $DM105_SS_ID AND study_event_definition_id = $M3_SED_ID LIMIT 1")
if [ -z "$M3_EVENT_ID" ]; then
    echo "Creating Month 3 event for DM-105..."
    oc_query "INSERT INTO study_event (study_subject_id, study_event_definition_id, status_id, owner_id, date_created, sample_ordinal, subject_event_status_id) VALUES ($DM105_SS_ID, $M3_SED_ID, 5, 1, NOW(), 1, 1)"
else
    echo "Setting Month 3 event to removed..."
    oc_query "UPDATE study_event SET status_id = 5 WHERE study_event_id = $M3_EVENT_ID"
fi

# 5. Ensure Month 6 event does NOT exist for DM-105
oc_query "DELETE FROM study_event WHERE study_subject_id = $DM105_SS_ID AND study_event_definition_id = $M6_SED_ID" 2>/dev/null || true

# 6. Clean up any discrepancy notes about "Restored Month 3"
oc_query "DELETE FROM discrepancy_note WHERE LOWER(description) LIKE '%restored month 3%' OR LOWER(detailed_notes) LIKE '%restored month 3%'" 2>/dev/null || true

# Record timestamp & baselines
date +%s > /tmp/task_start_timestamp
AUDIT_BASELINE=$(get_recent_audit_count 15)
echo "${AUDIT_BASELINE:-0}" > /tmp/audit_baseline_count
NONCE=$(generate_result_nonce)
echo "$NONCE" > /tmp/result_nonce

# Start Firefox and ensure login
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