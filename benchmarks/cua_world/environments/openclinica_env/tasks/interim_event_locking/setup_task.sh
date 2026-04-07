#!/bin/bash
echo "=== Setting up interim_event_locking task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_timestamp

# 1. Get DM Trial study_id
DM_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' AND status_id != 3 LIMIT 1")
if [ -z "$DM_STUDY_ID" ]; then
    echo "ERROR: Phase II Diabetes Trial (DM-TRIAL-2024) not found"
    exit 1
fi
echo "DM Trial study_id: $DM_STUDY_ID"

# Reset Study to Available (status=1) if it was locked or frozen previously
oc_query "UPDATE study SET status_id = 1 WHERE study_id = $DM_STUDY_ID"

# 2. Ensure Event Definitions exist
BASELINE_SED_ID=$(oc_query "SELECT study_event_definition_id FROM study_event_definition WHERE study_id = $DM_STUDY_ID AND name = 'Baseline Assessment' AND status_id != 3 LIMIT 1")
if [ -z "$BASELINE_SED_ID" ]; then
    oc_query "INSERT INTO study_event_definition (study_id, name, description, repeating, type, status_id, owner_id, date_created, oc_oid, ordinal) VALUES ($DM_STUDY_ID, 'Baseline Assessment', 'Baseline', false, 'Scheduled', 1, 1, NOW(), 'SE_BASE_01', 1)"
    BASELINE_SED_ID=$(oc_query "SELECT study_event_definition_id FROM study_event_definition WHERE study_id = $DM_STUDY_ID AND name = 'Baseline Assessment' LIMIT 1")
fi

WEEK4_SED_ID=$(oc_query "SELECT study_event_definition_id FROM study_event_definition WHERE study_id = $DM_STUDY_ID AND name = 'Week 4 Follow-up' AND status_id != 3 LIMIT 1")
if [ -z "$WEEK4_SED_ID" ]; then
    oc_query "INSERT INTO study_event_definition (study_id, name, description, repeating, type, status_id, owner_id, date_created, oc_oid, ordinal) VALUES ($DM_STUDY_ID, 'Week 4 Follow-up', 'Week 4', false, 'Scheduled', 1, 1, NOW(), 'SE_WK4_01', 2)"
    WEEK4_SED_ID=$(oc_query "SELECT study_event_definition_id FROM study_event_definition WHERE study_id = $DM_STUDY_ID AND name = 'Week 4 Follow-up' LIMIT 1")
fi

# 3. Setup Subjects and Events
for SUBJ in DM-101 DM-102 DM-103; do
    SS_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = '$SUBJ' AND study_id = $DM_STUDY_ID LIMIT 1")
    if [ -n "$SS_ID" ]; then
        echo "Configuring events for $SUBJ (study_subject_id=$SS_ID)..."
        
        # Clear existing events for this subject to ensure a clean starting state
        oc_query "DELETE FROM study_event WHERE study_subject_id = $SS_ID" 2>/dev/null || true
        
        # Insert Baseline Assessment as 'Completed' (subject_event_status_id = 4)
        oc_query "INSERT INTO study_event (study_event_definition_id, study_subject_id, subject_event_status_id, start_date, status_id, owner_id, date_created) VALUES ($BASELINE_SED_ID, $SS_ID, 4, CURRENT_DATE - INTERVAL '30 days', 1, 1, NOW())"
        
        # Insert Week 4 Follow-up as 'Scheduled' (subject_event_status_id = 1)
        oc_query "INSERT INTO study_event (study_event_definition_id, study_subject_id, subject_event_status_id, start_date, status_id, owner_id, date_created) VALUES ($WEEK4_SED_ID, $SS_ID, 1, CURRENT_DATE, 1, 1, NOW())"
    else
        echo "WARNING: $SUBJ not found in study!"
    fi
done

# 4. Save Audit log baseline & Nonce
AUDIT_BASELINE=$(get_recent_audit_count 15)
echo "${AUDIT_BASELINE:-0}" > /tmp/audit_baseline_count

NONCE=$(generate_result_nonce)
echo "Nonce: $NONCE"

# 5. Browser setup
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080/OpenClinica/MainMenu' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

wait_for_window "firefox\|mozilla\|OpenClinica" 30
ensure_logged_in
switch_active_study "DM-TRIAL-2024"
focus_firefox
sleep 1

# 6. Capture initial state
take_screenshot /tmp/task_start_screenshot.png

echo "=== interim_event_locking setup complete ==="