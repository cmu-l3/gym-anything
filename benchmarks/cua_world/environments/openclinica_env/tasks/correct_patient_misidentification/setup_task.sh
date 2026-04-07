#!/bin/bash
echo "=== Setting up correct_patient_misidentification task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_timestamp

# 1. Get DM Trial study_id
DM_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' AND status_id != 3 LIMIT 1")
if [ -z "$DM_STUDY_ID" ]; then
    echo "ERROR: Phase II Diabetes Trial (DM-TRIAL-2024) not found in database"
    exit 1
fi
echo "DM Trial study_id: $DM_STUDY_ID"

# 2. Ensure "Week 4 Follow-up" event definition exists
WEEK4_SED_ID=$(oc_query "SELECT study_event_definition_id FROM study_event_definition WHERE name = 'Week 4 Follow-up' AND study_id = $DM_STUDY_ID AND status_id != 3 LIMIT 1")
if [ -z "$WEEK4_SED_ID" ]; then
    echo "Adding Week 4 Follow-up event definition..."
    oc_query "INSERT INTO study_event_definition (study_id, name, description, repeating, type, status_id, owner_id, date_created, oc_oid, ordinal) VALUES ($DM_STUDY_ID, 'Week 4 Follow-up', 'Four-week follow-up visit', true, 'Scheduled', 1, 1, NOW(), 'SE_DM_WEEK4', 2)"
    WEEK4_SED_ID=$(oc_query "SELECT study_event_definition_id FROM study_event_definition WHERE name = 'Week 4 Follow-up' AND study_id = $DM_STUDY_ID AND status_id != 3 LIMIT 1")
fi
echo "Week 4 Follow-up SED ID: $WEEK4_SED_ID"

# 3. Get Subject IDs
DM101_SS_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = 'DM-101' AND study_id = $DM_STUDY_ID AND status_id != 3 LIMIT 1")
DM102_SS_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = 'DM-102' AND study_id = $DM_STUDY_ID AND status_id != 3 LIMIT 1")

if [ -z "$DM101_SS_ID" ] || [ -z "$DM102_SS_ID" ]; then
    echo "ERROR: Required subjects DM-101 or DM-102 not found."
    exit 1
fi
echo "DM-101 SS_ID: $DM101_SS_ID | DM-102 SS_ID: $DM102_SS_ID"

# 4. Clean DM-102's "Week 4 Follow-up" event (Must be a clean slate for the agent)
oc_query "DELETE FROM item_data WHERE event_crf_id IN (SELECT event_crf_id FROM event_crf WHERE study_event_id IN (SELECT study_event_id FROM study_event WHERE study_subject_id = $DM102_SS_ID AND study_event_definition_id = $WEEK4_SED_ID))" 2>/dev/null || true
oc_query "DELETE FROM event_crf WHERE study_event_id IN (SELECT study_event_id FROM study_event WHERE study_subject_id = $DM102_SS_ID AND study_event_definition_id = $WEEK4_SED_ID)" 2>/dev/null || true
oc_query "DELETE FROM study_event WHERE study_subject_id = $DM102_SS_ID AND study_event_definition_id = $WEEK4_SED_ID" 2>/dev/null || true
echo "Cleaned DM-102 pre-existing events."

# 5. Seed DM-101's "Week 4 Follow-up" event with the bad data state
# Remove any existing to prevent duplicates
oc_query "DELETE FROM item_data WHERE event_crf_id IN (SELECT event_crf_id FROM event_crf WHERE study_event_id IN (SELECT study_event_id FROM study_event WHERE study_subject_id = $DM101_SS_ID AND study_event_definition_id = $WEEK4_SED_ID))" 2>/dev/null || true
oc_query "DELETE FROM event_crf WHERE study_event_id IN (SELECT study_event_id FROM study_event WHERE study_subject_id = $DM101_SS_ID AND study_event_definition_id = $WEEK4_SED_ID)" 2>/dev/null || true
oc_query "DELETE FROM study_event WHERE study_subject_id = $DM101_SS_ID AND study_event_definition_id = $WEEK4_SED_ID" 2>/dev/null || true

# Insert the scheduled event with status_id=1 (Available)
# Using subject_event_status_id=1 (Scheduled)
oc_query "INSERT INTO study_event (study_subject_id, study_event_definition_id, start_date, status_id, owner_id, date_created, sample_ordinal, subject_event_status_id) VALUES ($DM101_SS_ID, $WEEK4_SED_ID, CURRENT_DATE - INTERVAL '1 day', 1, 1, NOW(), 1, 1)"
echo "Seeded DM-101 with incorrect 'Week 4 Follow-up' scheduled event."

# 6. Record baseline audit log
AUDIT_BASELINE=$(get_recent_audit_count 15)
echo "${AUDIT_BASELINE:-0}" > /tmp/audit_baseline_count
echo "Audit log baseline: ${AUDIT_BASELINE:-0}"

# 7. Generate Nonce
NONCE=$(generate_result_nonce)
echo "Nonce: $NONCE"

# 8. Start Firefox and login
if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox 'http://localhost:8080/OpenClinica/MainMenu' > /tmp/firefox_task.log 2>&1 &
    sleep 5
fi

wait_for_window "firefox\|mozilla\|OpenClinica" 30
ensure_logged_in
switch_active_study "DM-TRIAL-2024"
focus_firefox
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== correct_patient_misidentification setup complete ==="