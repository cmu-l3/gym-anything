#!/bin/bash
echo "=== Setting up schedule_and_track_visits task ==="

source /workspace/scripts/task_utils.sh

# Get the DM Trial study_id
DM_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' AND status_id != 3 LIMIT 1")
if [ -z "$DM_STUDY_ID" ]; then
    echo "ERROR: Phase II Diabetes Trial not found in database"
    exit 1
fi
echo "DM Trial study_id: $DM_STUDY_ID"

# Add event definitions to DM Trial if they don't exist
BASELINE_EXISTS=$(oc_query "SELECT COUNT(*) FROM study_event_definition WHERE study_id = $DM_STUDY_ID AND name = 'Baseline Assessment' AND status_id != 3")
if [ "$BASELINE_EXISTS" = "0" ] || [ -z "$BASELINE_EXISTS" ]; then
    echo "Adding Baseline Assessment event definition to DM Trial..."
    oc_query "INSERT INTO study_event_definition (study_id, name, description, repeating, type, status_id, owner_id, date_created, oc_oid, ordinal) VALUES ($DM_STUDY_ID, 'Baseline Assessment', 'Initial baseline study visit', false, 'Scheduled', 1, 1, NOW(), 'SE_DM_BASELINE', 1)"
    echo "Baseline Assessment event definition added"
else
    echo "Baseline Assessment event definition already exists"
fi

WEEK4_EXISTS=$(oc_query "SELECT COUNT(*) FROM study_event_definition WHERE study_id = $DM_STUDY_ID AND name = 'Week 4 Follow-up' AND status_id != 3")
if [ "$WEEK4_EXISTS" = "0" ] || [ -z "$WEEK4_EXISTS" ]; then
    echo "Adding Week 4 Follow-up event definition to DM Trial..."
    oc_query "INSERT INTO study_event_definition (study_id, name, description, repeating, type, status_id, owner_id, date_created, oc_oid, ordinal) VALUES ($DM_STUDY_ID, 'Week 4 Follow-up', 'Four-week follow-up visit for safety and efficacy assessment', true, 'Scheduled', 1, 1, NOW(), 'SE_DM_WEEK4', 2)"
    echo "Week 4 Follow-up event definition added"
else
    echo "Week 4 Follow-up event definition already exists"
fi

# Record initial state
INITIAL_EVENT_COUNT=$(oc_query "SELECT COUNT(*) FROM study_event se JOIN study_subject ss ON se.study_subject_id = ss.study_subject_id WHERE ss.study_id = $DM_STUDY_ID")
INITIAL_SUBJECT_COUNT=$(oc_query "SELECT COUNT(*) FROM study_subject WHERE study_id = $DM_STUDY_ID AND status_id != 3")
echo "${INITIAL_EVENT_COUNT:-0}" > /tmp/initial_event_count
echo "${INITIAL_SUBJECT_COUNT:-0}" > /tmp/initial_subject_count
echo "Initial event count: ${INITIAL_EVENT_COUNT:-0}"
echo "Initial subject count: ${INITIAL_SUBJECT_COUNT:-0}"

# Verify pre-existing subjects exist
for SUBJ_LABEL in DM-101 DM-102 DM-103; do
    SS_CHECK=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = '$SUBJ_LABEL' AND study_id = $DM_STUDY_ID LIMIT 1")
    if [ -z "$SS_CHECK" ]; then
        echo "WARNING: Subject $SUBJ_LABEL not found in DM Trial"
    else
        echo "Confirmed: Subject $SUBJ_LABEL exists (study_subject_id=$SS_CHECK)"
    fi
done

# Ensure DM-104 does NOT already exist (clean state)
DM104_EXISTS=$(oc_query "SELECT COUNT(*) FROM study_subject WHERE label = 'DM-104' AND study_id = $DM_STUDY_ID")
if [ "$DM104_EXISTS" != "0" ] && [ -n "$DM104_EXISTS" ]; then
    echo "Removing pre-existing DM-104 record for clean state..."
    DM104_SS_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = 'DM-104' AND study_id = $DM_STUDY_ID LIMIT 1")
    if [ -n "$DM104_SS_ID" ]; then
        oc_query "DELETE FROM study_event WHERE study_subject_id = $DM104_SS_ID" 2>/dev/null || true
        DM104_SUBJ_ID=$(oc_query "SELECT subject_id FROM study_subject WHERE study_subject_id = $DM104_SS_ID LIMIT 1")
        oc_query "DELETE FROM study_subject WHERE study_subject_id = $DM104_SS_ID" 2>/dev/null || true
        if [ -n "$DM104_SUBJ_ID" ]; then
            oc_query "DELETE FROM subject WHERE subject_id = $DM104_SUBJ_ID" 2>/dev/null || true
        fi
    fi
    echo "DM-104 cleaned up"
fi

# Remove any pre-existing events for DM-101 and DM-102 (clean state for the task)
for SUBJ_LABEL in DM-101 DM-102; do
    SS_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = '$SUBJ_LABEL' AND study_id = $DM_STUDY_ID LIMIT 1")
    if [ -n "$SS_ID" ]; then
        oc_query "DELETE FROM study_event WHERE study_subject_id = $SS_ID" 2>/dev/null || true
        echo "Cleared pre-existing events for $SUBJ_LABEL"
    fi
done

# Record fresh initial counts after cleanup
INITIAL_EVENT_COUNT=$(oc_query "SELECT COUNT(*) FROM study_event se JOIN study_subject ss ON se.study_subject_id = ss.study_subject_id WHERE ss.study_id = $DM_STUDY_ID")
INITIAL_SUBJECT_COUNT=$(oc_query "SELECT COUNT(*) FROM study_subject WHERE study_id = $DM_STUDY_ID AND status_id != 3")
echo "${INITIAL_EVENT_COUNT:-0}" > /tmp/initial_event_count
echo "${INITIAL_SUBJECT_COUNT:-0}" > /tmp/initial_subject_count

# Record timestamp
date +%s > /tmp/task_start_timestamp

# Ensure Firefox is running
if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox 'http://localhost:8080/OpenClinica/MainMenu' > /tmp/firefox_task.log 2>&1 &
    sleep 5
fi

wait_for_window "firefox\|mozilla\|OpenClinica" 30
ensure_logged_in
switch_active_study "DM-TRIAL-2024"
focus_firefox
sleep 1

# Record audit baseline
AUDIT_BASELINE=$(get_recent_audit_count 15)
echo "${AUDIT_BASELINE:-0}" > /tmp/audit_baseline_count
echo "Audit baseline: ${AUDIT_BASELINE:-0}"

NONCE=$(generate_result_nonce)
echo "Nonce: $NONCE"

take_screenshot /tmp/task_start_screenshot.png

echo "=== schedule_and_track_visits setup complete ==="
