#!/bin/bash
echo "=== Setting up create_subject_group_class task ==="

source /workspace/scripts/task_utils.sh

# Wait for OpenClinica to be ready before DB operations
wait_for_window "firefox\|mozilla\|OpenClinica" 30 || true

DM_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' LIMIT 1")
if [ -z "$DM_STUDY_ID" ]; then
    echo "ERROR: Phase II Diabetes Trial not found in database"
    exit 1
fi

echo "Removing any existing 'Treatment Arm' classes for clean state..."
CLASS_IDS=$(oc_query "SELECT study_group_class_id FROM study_group_class WHERE study_id = $DM_STUDY_ID AND name = 'Treatment Arm'")
if [ -n "$CLASS_IDS" ]; then
    for CID in $CLASS_IDS; do
        if [ -n "$CID" ] && [ "$CID" -eq "$CID" ] 2>/dev/null; then
            oc_query "DELETE FROM study_group WHERE study_group_class_id = $CID" 2>/dev/null || true
            oc_query "DELETE FROM study_group_class WHERE study_group_class_id = $CID" 2>/dev/null || true
        fi
    done
fi

INITIAL_CLASS_COUNT=$(oc_query "SELECT COUNT(*) FROM study_group_class" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
INITIAL_GROUP_COUNT=$(oc_query "SELECT COUNT(*) FROM study_group" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
echo "${INITIAL_CLASS_COUNT:-0}" > /tmp/initial_class_count
echo "${INITIAL_GROUP_COUNT:-0}" > /tmp/initial_group_count

date +%s > /tmp/task_start_timestamp

# Create anti-gaming nonce
NONCE=$(cat /dev/urandom 2>/dev/null | tr -dc 'a-zA-Z0-9' 2>/dev/null | fold -w 32 2>/dev/null | head -n 1 || echo "1234567890abcdef")
echo "$NONCE" > /tmp/result_nonce
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

# Capture audit baseline to prevent direct DB injection
if type get_recent_audit_count >/dev/null 2>&1; then
    AUDIT_BASELINE=$(get_recent_audit_count 15)
    echo "${AUDIT_BASELINE:-0}" > /tmp/audit_baseline_count
fi

take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="