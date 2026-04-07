#!/bin/bash
echo "=== Exporting subject_restoration_and_lock result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# Resolve Study and SED
DM_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' LIMIT 1")
SED_ID=$(oc_query "SELECT study_event_definition_id FROM study_event_definition WHERE name = 'Baseline Assessment' AND study_id = $DM_STUDY_ID LIMIT 1")

# Extract DM-105 data
DM105_SS_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = 'DM-105' AND study_id = $DM_STUDY_ID LIMIT 1")
DM105_STATUS="0"
DM105_EVENT_STATUS="0"

if [ -n "$DM105_SS_ID" ]; then
    DM105_STATUS=$(oc_query "SELECT status_id FROM study_subject WHERE study_subject_id = $DM105_SS_ID LIMIT 1")
    if [ -n "$SED_ID" ]; then
        DM105_EVENT_STATUS=$(oc_query "SELECT subject_event_status_id FROM study_event WHERE study_subject_id = $DM105_SS_ID AND study_event_definition_id = $SED_ID LIMIT 1")
    fi
fi

# Extract DM-101 data (Collateral check)
DM101_SS_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = 'DM-101' AND study_id = $DM_STUDY_ID LIMIT 1")
DM101_STATUS="0"
DM101_EVENT_STATUS="0"

if [ -n "$DM101_SS_ID" ]; then
    DM101_STATUS=$(oc_query "SELECT status_id FROM study_subject WHERE study_subject_id = $DM101_SS_ID LIMIT 1")
    if [ -n "$SED_ID" ]; then
        DM101_EVENT_STATUS=$(oc_query "SELECT subject_event_status_id FROM study_event WHERE study_subject_id = $DM101_SS_ID AND study_event_definition_id = $SED_ID LIMIT 1")
    fi
fi

# Audit logs
AUDIT_LOG_COUNT=$(get_recent_audit_count 60)
AUDIT_BASELINE_COUNT=$(cat /tmp/audit_baseline_count 2>/dev/null || echo "0")

# Construct JSON
TEMP_JSON=$(mktemp /tmp/subject_restoration_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "dm105_status_id": ${DM105_STATUS:-0},
    "dm105_event_status_id": ${DM105_EVENT_STATUS:-0},
    "dm101_status_id": ${DM101_STATUS:-0},
    "dm101_event_status_id": ${DM101_EVENT_STATUS:-0},
    "audit_log_count": ${AUDIT_LOG_COUNT:-0},
    "audit_baseline_count": ${AUDIT_BASELINE_COUNT:-0},
    "result_nonce": "$(cat /tmp/result_nonce 2>/dev/null || echo "")",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location safely
rm -f /tmp/subject_restoration_result.json 2>/dev/null || sudo rm -f /tmp/subject_restoration_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/subject_restoration_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/subject_restoration_result.json
chmod 666 /tmp/subject_restoration_result.json 2>/dev/null || sudo chmod 666 /tmp/subject_restoration_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Export complete:"
cat /tmp/subject_restoration_result.json