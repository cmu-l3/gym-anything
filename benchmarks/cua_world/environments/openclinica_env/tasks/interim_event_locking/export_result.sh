#!/bin/bash
echo "=== Exporting interim_event_locking result ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Resolve IDs
DM_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' LIMIT 1")
BASELINE_SED_ID=$(oc_query "SELECT study_event_definition_id FROM study_event_definition WHERE study_id = $DM_STUDY_ID AND name = 'Baseline Assessment' AND status_id != 3 LIMIT 1")
WEEK4_SED_ID=$(oc_query "SELECT study_event_definition_id FROM study_event_definition WHERE study_id = $DM_STUDY_ID AND name = 'Week 4 Follow-up' AND status_id != 3 LIMIT 1")

# Extract Study Status
STUDY_STATUS=$(oc_query "SELECT status_id FROM study WHERE study_id = $DM_STUDY_ID LIMIT 1")

# Extract Event Statuses for each subject
declare -A BASELINE_STATUSES
declare -A WEEK4_STATUSES

for SUBJ in DM-101 DM-102 DM-103; do
    SS_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = '$SUBJ' AND study_id = $DM_STUDY_ID LIMIT 1")
    if [ -n "$SS_ID" ]; then
        B_STAT=$(oc_query "SELECT subject_event_status_id FROM study_event WHERE study_subject_id = $SS_ID AND study_event_definition_id = $BASELINE_SED_ID ORDER BY study_event_id DESC LIMIT 1")
        W_STAT=$(oc_query "SELECT subject_event_status_id FROM study_event WHERE study_subject_id = $SS_ID AND study_event_definition_id = $WEEK4_SED_ID ORDER BY study_event_id DESC LIMIT 1")
        
        BASELINE_STATUSES["$SUBJ"]=${B_STAT:-0}
        WEEK4_STATUSES["$SUBJ"]=${W_STAT:-0}
    else
        BASELINE_STATUSES["$SUBJ"]=0
        WEEK4_STATUSES["$SUBJ"]=0
    fi
done

# Audit counts
AUDIT_LOG_COUNT=$(get_recent_audit_count 60)
AUDIT_BASELINE_COUNT=$(cat /tmp/audit_baseline_count 2>/dev/null || echo "0")
NONCE=$(cat /tmp/result_nonce 2>/dev/null || echo "MISSING")

# Export to JSON
TEMP_JSON=$(mktemp /tmp/interim_event_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "study_status_id": ${STUDY_STATUS:-0},
    "dm101_baseline_status": ${BASELINE_STATUSES["DM-101"]},
    "dm102_baseline_status": ${BASELINE_STATUSES["DM-102"]},
    "dm103_baseline_status": ${BASELINE_STATUSES["DM-103"]},
    "dm101_week4_status": ${WEEK4_STATUSES["DM-101"]},
    "dm102_week4_status": ${WEEK4_STATUSES["DM-102"]},
    "dm103_week4_status": ${WEEK4_STATUSES["DM-103"]},
    "audit_log_count": $AUDIT_LOG_COUNT,
    "audit_baseline_count": $AUDIT_BASELINE_COUNT,
    "result_nonce": "$NONCE"
}
EOF

# Move securely
rm -f /tmp/interim_event_locking_result.json 2>/dev/null || sudo rm -f /tmp/interim_event_locking_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/interim_event_locking_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/interim_event_locking_result.json
chmod 666 /tmp/interim_event_locking_result.json 2>/dev/null || sudo chmod 666 /tmp/interim_event_locking_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Export complete:"
cat /tmp/interim_event_locking_result.json