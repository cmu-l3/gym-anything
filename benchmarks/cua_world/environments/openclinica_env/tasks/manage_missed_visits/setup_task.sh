#!/bin/bash
echo "=== Setting up manage_missed_visits task ==="

source /workspace/scripts/task_utils.sh

# 1. Get DM Trial study_id
DM_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' AND status_id != 3 LIMIT 1")
if [ -z "$DM_STUDY_ID" ]; then
    echo "ERROR: Phase II Diabetes Trial not found in database"
    exit 1
fi
echo "DM Trial study_id: $DM_STUDY_ID"

# 2. Ensure event definitions exist
BASELINE_EXISTS=$(oc_query "SELECT COUNT(*) FROM study_event_definition WHERE study_id = $DM_STUDY_ID AND name = 'Baseline Assessment' AND status_id != 3")
if [ "$BASELINE_EXISTS" = "0" ] || [ -z "$BASELINE_EXISTS" ]; then
    echo "Adding Baseline Assessment event definition to DM Trial..."
    oc_query "INSERT INTO study_event_definition (study_id, name, description, repeating, type, status_id, owner_id, date_created, oc_oid, ordinal) VALUES ($DM_STUDY_ID, 'Baseline Assessment', 'Initial baseline study visit', false, 'Scheduled', 1, 1, NOW(), 'SE_DM_BASELINE', 1)"
fi

WEEK4_EXISTS=$(oc_query "SELECT COUNT(*) FROM study_event_definition WHERE study_id = $DM_STUDY_ID AND name = 'Week 4 Follow-up' AND status_id != 3")
if [ "$WEEK4_EXISTS" = "0" ] || [ -z "$WEEK4_EXISTS" ]; then
    echo "Adding Week 4 Follow-up event definition to DM Trial..."
    oc_query "INSERT INTO study_event_definition (study_id, name, description, repeating, type, status_id, owner_id, date_created, oc_oid, ordinal) VALUES ($DM_STUDY_ID, 'Week 4 Follow-up', 'Four-week follow-up visit', true, 'Scheduled', 1, 1, NOW(), 'SE_DM_WEEK4', 2)"
fi

SED_BASE=$(oc_query "SELECT study_event_definition_id FROM study_event_definition WHERE name = 'Baseline Assessment' AND study_id = $DM_STUDY_ID AND status_id != 3 LIMIT 1")
SED_WK4=$(oc_query "SELECT study_event_definition_id FROM study_event_definition WHERE name = 'Week 4 Follow-up' AND study_id = $DM_STUDY_ID AND status_id != 3 LIMIT 1")

# 3. Get Subject IDs
SS_101=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = 'DM-101' AND study_id = $DM_STUDY_ID LIMIT 1")
SS_102=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = 'DM-102' AND study_id = $DM_STUDY_ID LIMIT 1")
SS_103=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = 'DM-103' AND study_id = $DM_STUDY_ID LIMIT 1")

if [ -z "$SS_101" ] || [ -z "$SS_102" ] || [ -z "$SS_103" ]; then
    echo "ERROR: Target subjects (DM-101, DM-102, DM-103) not found."
    exit 1
fi

echo "Subject IDs verified: DM-101 ($SS_101), DM-102 ($SS_102), DM-103 ($SS_103)"

# 4. Clean existing notes containing the task keywords to ensure a clean state
oc_query "DELETE FROM discrepancy_note WHERE LOWER(description) LIKE '%covid%' OR LOWER(detailed_notes) LIKE '%covid%'" 2>/dev/null || true
oc_query "DELETE FROM discrepancy_note WHERE LOWER(description) LIKE '%transportation%' OR LOWER(detailed_notes) LIKE '%transportation%'" 2>/dev/null || true
oc_query "DELETE FROM discrepancy_note WHERE LOWER(description) LIKE '%withdrew%' OR LOWER(detailed_notes) LIKE '%withdrew%'" 2>/dev/null || true

# 5. Reset events to "Scheduled" (status 1) with past dates so they appear missed
# DM-101 Week 4
oc_query "DELETE FROM study_event WHERE study_subject_id = $SS_101 AND study_event_definition_id = $SED_WK4" 2>/dev/null || true
oc_query "INSERT INTO study_event (study_subject_id, study_event_definition_id, subject_event_status_id, start_date, status_id, owner_id, date_created) VALUES ($SS_101, $SED_WK4, 1, CURRENT_DATE - INTERVAL '10 days', 1, 1, NOW())"

# DM-102 Baseline
oc_query "DELETE FROM study_event WHERE study_subject_id = $SS_102 AND study_event_definition_id = $SED_BASE" 2>/dev/null || true
oc_query "INSERT INTO study_event (study_subject_id, study_event_definition_id, subject_event_status_id, start_date, status_id, owner_id, date_created) VALUES ($SS_102, $SED_BASE, 1, CURRENT_DATE - INTERVAL '14 days', 1, 1, NOW())"

# DM-103 Week 4
oc_query "DELETE FROM study_event WHERE study_subject_id = $SS_103 AND study_event_definition_id = $SED_WK4" 2>/dev/null || true
oc_query "INSERT INTO study_event (study_subject_id, study_event_definition_id, subject_event_status_id, start_date, status_id, owner_id, date_created) VALUES ($SS_103, $SED_WK4, 1, CURRENT_DATE - INTERVAL '7 days', 1, 1, NOW())"

echo "Events reset to Scheduled status."

# 6. Record timestamp and start browser
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

# 7. Record anti-gaming baselines
AUDIT_BASELINE=$(get_recent_audit_count 15)
echo "${AUDIT_BASELINE:-0}" > /tmp/audit_baseline_count
echo "Audit log baseline: ${AUDIT_BASELINE:-0}"

NONCE=$(generate_result_nonce)
echo "Nonce generated for result validation."

take_screenshot /tmp/task_start_screenshot.png

echo "=== manage_missed_visits setup complete ==="