#!/bin/bash
echo "=== Setting up protocol_amendment_events task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_timestamp

# ── 1. Resolve Study ID ────────────────────────────────────────────────────────
DM_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' LIMIT 1")
if [ -z "$DM_STUDY_ID" ]; then
    echo "ERROR: Phase II Diabetes Trial not found in database"
    exit 1
fi
echo "DM Trial study_id: $DM_STUDY_ID"
echo "$DM_STUDY_ID" > /tmp/dm_study_id

# ── 2. Clean Up State for Idempotency ──────────────────────────────────────────
echo "Cleaning up any events from previous runs..."
oc_query "DELETE FROM study_event_definition WHERE study_id = $DM_STUDY_ID AND (
    LOWER(name) LIKE '%week%4%safety%' OR 
    LOWER(name) LIKE '%week%12%efficacy%' OR 
    LOWER(name) LIKE '%unscheduled%safety%' OR 
    LOWER(name) LIKE '%end%treatment%'
)" 2>/dev/null || true

# ── 3. Restore 'Baseline Assessment' (Must be kept) ────────────────────────────
BASELINE_EXISTS=$(oc_query "SELECT COUNT(*) FROM study_event_definition WHERE study_id = $DM_STUDY_ID AND name = 'Baseline Assessment'")
if [ "$BASELINE_EXISTS" = "0" ]; then
    echo "Restoring Baseline Assessment..."
    oc_query "INSERT INTO study_event_definition (study_id, name, description, repeating, type, status_id, owner_id, date_created, oc_oid, ordinal) VALUES ($DM_STUDY_ID, 'Baseline Assessment', 'Initial baseline study visit', false, 'Scheduled', 1, 1, NOW(), 'SE_DM_BASELINE', 1)"
else
    oc_query "UPDATE study_event_definition SET status_id = 1 WHERE study_id = $DM_STUDY_ID AND name = 'Baseline Assessment'"
fi

# ── 4. Restore 'Follow-up Visit' (Must be removed by agent) ────────────────────
FOLLOWUP_EXISTS=$(oc_query "SELECT COUNT(*) FROM study_event_definition WHERE study_id = $DM_STUDY_ID AND name = 'Follow-up Visit'")
if [ "$FOLLOWUP_EXISTS" = "0" ]; then
    echo "Restoring Follow-up Visit..."
    oc_query "INSERT INTO study_event_definition (study_id, name, description, repeating, type, status_id, owner_id, date_created, oc_oid, ordinal) VALUES ($DM_STUDY_ID, 'Follow-up Visit', 'Follow-up visit for safety and efficacy assessment', true, 'Scheduled', 1, 1, NOW(), 'SE_DM_FOLLOWUP', 2)"
else
    oc_query "UPDATE study_event_definition SET status_id = 1 WHERE study_id = $DM_STUDY_ID AND name = 'Follow-up Visit'"
fi

# ── 5. Record Baseline Data ────────────────────────────────────────────────────
INITIAL_EVENT_COUNT=$(oc_query "SELECT COUNT(*) FROM study_event_definition WHERE study_id = $DM_STUDY_ID AND status_id = 1")
echo "${INITIAL_EVENT_COUNT:-0}" > /tmp/initial_event_count

AUDIT_BASELINE=$(get_recent_audit_count 15)
echo "${AUDIT_BASELINE:-0}" > /tmp/audit_baseline_count

NONCE=$(generate_result_nonce)
echo "Nonce: $NONCE"

# ── 6. UI Navigation and Focusing ──────────────────────────────────────────────
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

echo "=== protocol_amendment_events setup complete ==="