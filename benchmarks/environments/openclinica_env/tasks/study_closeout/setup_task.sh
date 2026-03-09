#!/bin/bash
echo "=== Setting up study_closeout task ==="

source /workspace/scripts/task_utils.sh

# --- Get DM Trial study_id ---
DM_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' AND status_id != 3 LIMIT 1")
if [ -z "$DM_STUDY_ID" ]; then
    echo "ERROR: Phase II Diabetes Trial (DM-TRIAL-2024) not found in database"
    exit 1
fi
echo "DM Trial study_id: $DM_STUDY_ID"

# --- Get AP Pilot study_id ---
AP_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'AP-PILOT-2022' AND status_id != 3 LIMIT 1")
if [ -z "$AP_STUDY_ID" ]; then
    echo "ERROR: Asthma Prevention Pilot (AP-PILOT-2022) not found in database"
    exit 1
fi
echo "AP Pilot study_id: $AP_STUDY_ID"

# --- Verify DM Trial is in expected starting state (status_id=1, Available) ---
DM_STATUS=$(oc_query "SELECT status_id FROM study WHERE study_id = $DM_STUDY_ID LIMIT 1")
echo "DM Trial current status_id: $DM_STATUS"
if [ "$DM_STATUS" != "1" ]; then
    echo "WARNING: DM Trial is not in Available state (status_id=1), resetting to Available..."
    oc_query "UPDATE study SET status_id = 1 WHERE study_id = $DM_STUDY_ID"
    echo "DM Trial reset to Available (status_id=1)"
fi

# --- Verify AP Pilot is in expected starting state (status_id=4, Completed) ---
AP_STATUS=$(oc_query "SELECT status_id FROM study WHERE study_id = $AP_STUDY_ID LIMIT 1")
echo "AP Pilot current status_id: $AP_STATUS"
if [ "$AP_STATUS" != "4" ]; then
    echo "WARNING: AP Pilot is not in Completed state (status_id=4), resetting to Completed..."
    oc_query "UPDATE study SET status_id = 4 WHERE study_id = $AP_STUDY_ID"
    echo "AP Pilot reset to Completed (status_id=4)"
fi

# --- Ensure DM-103 is active (status_id=1) in study_subject ---
DM103_SS_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = 'DM-103' AND study_id = $DM_STUDY_ID LIMIT 1")
if [ -z "$DM103_SS_ID" ]; then
    echo "ERROR: Subject DM-103 not found in DM Trial"
    exit 1
fi
DM103_STATUS=$(oc_query "SELECT status_id FROM study_subject WHERE study_subject_id = $DM103_SS_ID LIMIT 1")
echo "DM-103 current study_subject status_id: $DM103_STATUS"
if [ "$DM103_STATUS" != "1" ]; then
    echo "Resetting DM-103 to active status (status_id=1)..."
    oc_query "UPDATE study_subject SET status_id = 1 WHERE study_subject_id = $DM103_SS_ID"
    echo "DM-103 reset to active"
fi

# --- Verify other DM subjects exist ---
for SUBJ_LABEL in DM-101 DM-102; do
    SS_CHECK=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = '$SUBJ_LABEL' AND study_id = $DM_STUDY_ID LIMIT 1")
    if [ -z "$SS_CHECK" ]; then
        echo "WARNING: Subject $SUBJ_LABEL not found in DM Trial"
    else
        echo "Confirmed: Subject $SUBJ_LABEL exists (study_subject_id=$SS_CHECK)"
    fi
done

# --- Remove any existing "End of Study Assessment" event definition for clean state ---
EOS_EXISTS=$(oc_query "SELECT COUNT(*) FROM study_event_definition WHERE study_id = $DM_STUDY_ID AND LOWER(name) LIKE '%end%' AND LOWER(name) LIKE '%study%' AND status_id != 3")
if [ "${EOS_EXISTS:-0}" != "0" ] && [ -n "$EOS_EXISTS" ]; then
    echo "Removing pre-existing 'End of Study Assessment' event definition(s) for clean state..."
    oc_query "DELETE FROM study_event_definition WHERE study_id = $DM_STUDY_ID AND LOWER(name) LIKE '%end%' AND LOWER(name) LIKE '%study%'" 2>/dev/null || true
    echo "Cleaned up pre-existing End of Study event definition(s)"
fi

# Also remove any 'final assessment' variants
FINAL_EXISTS=$(oc_query "SELECT COUNT(*) FROM study_event_definition WHERE study_id = $DM_STUDY_ID AND LOWER(name) LIKE '%final%assess%' AND status_id != 3")
if [ "${FINAL_EXISTS:-0}" != "0" ] && [ -n "$FINAL_EXISTS" ]; then
    echo "Removing pre-existing 'final assessment' event definition(s)..."
    oc_query "DELETE FROM study_event_definition WHERE study_id = $DM_STUDY_ID AND LOWER(name) LIKE '%final%assess%'" 2>/dev/null || true
    echo "Cleaned up pre-existing final assessment event definition(s)"
fi

# --- Remove any existing exports from Desktop/Downloads (clean state for export check) ---
echo "Cleaning up existing export files from Desktop and Downloads..."
find /home/ga/Desktop /home/ga/Downloads -maxdepth 2 -type f \( \
    -name "*.xml" -o -name "*.zip" -o -name "*.xls" -o \
    -name "*.xlsx" -o -name "*.csv" -o -name "*.ods" \
\) -delete 2>/dev/null || true
echo "Export cleanup complete"

# --- Record baseline state ---
DM_TRIAL_STATUS=$(oc_query "SELECT status_id FROM study WHERE study_id = $DM_STUDY_ID LIMIT 1")
AP_PILOT_STATUS=$(oc_query "SELECT status_id FROM study WHERE study_id = $AP_STUDY_ID LIMIT 1")
DM_TRIAL_EVENT_DEF_COUNT=$(oc_query "SELECT COUNT(*) FROM study_event_definition WHERE study_id = $DM_STUDY_ID AND status_id != 3")
DM103_STATUS_NOW=$(oc_query "SELECT status_id FROM study_subject WHERE study_subject_id = $DM103_SS_ID LIMIT 1")

echo "${DM_TRIAL_STATUS:-1}" > /tmp/baseline_dm_trial_status
echo "${AP_PILOT_STATUS:-4}" > /tmp/baseline_ap_pilot_status
echo "${DM_TRIAL_EVENT_DEF_COUNT:-0}" > /tmp/baseline_dm_trial_event_def_count
echo "${DM103_STATUS_NOW:-1}" > /tmp/baseline_dm103_status

echo "Baseline dm_trial_status: ${DM_TRIAL_STATUS:-1}"
echo "Baseline ap_pilot_status: ${AP_PILOT_STATUS:-4}"
echo "Baseline dm_trial_event_def_count: ${DM_TRIAL_EVENT_DEF_COUNT:-0}"
echo "Baseline dm103_status: ${DM103_STATUS_NOW:-1}"

# --- Record timestamp for export file recency check ---
touch /tmp/task_start_timestamp
date +%s > /tmp/task_start_epoch
echo "Task start timestamp recorded"

# --- Ensure Firefox is running ---
if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox 'http://localhost:8080/OpenClinica/MainMenu' > /tmp/firefox_task.log 2>&1 &
    sleep 5
fi

wait_for_window "firefox\|mozilla\|OpenClinica" 30
ensure_logged_in

# NOTE: Do NOT call switch_active_study here — the agent must navigate between studies themselves.
# This is part of what makes the task "very hard".

focus_firefox
sleep 1

# --- Record audit baseline ---
AUDIT_BASELINE=$(get_recent_audit_count 15)
echo "${AUDIT_BASELINE:-0}" > /tmp/audit_baseline_count
echo "Audit baseline: ${AUDIT_BASELINE:-0}"

# --- Generate nonce for result integrity ---
NONCE=$(generate_result_nonce)
echo "Nonce: $NONCE"

# --- Take initial screenshot ---
take_screenshot /tmp/task_start_screenshot.png

echo "=== study_closeout setup complete ==="
echo "DM Trial (DM-TRIAL-2024) status: Available (1)"
echo "AP Pilot (AP-PILOT-2022) status: Completed (4)"
echo "DM-103 status: Active (1)"
echo "Agent must discover and perform all 5 subtasks independently."
