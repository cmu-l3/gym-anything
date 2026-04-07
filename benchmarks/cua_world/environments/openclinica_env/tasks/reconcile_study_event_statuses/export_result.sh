#!/bin/bash
echo "=== Exporting reconcile_study_event_statuses result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Resolve IDs
DM_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' AND status_id != 3 LIMIT 1")
BASELINE_SED_ID=$(oc_query "SELECT study_event_definition_id FROM study_event_definition WHERE study_id = $DM_STUDY_ID AND name = 'Baseline Assessment' AND status_id != 3 LIMIT 1")

# Extract statuses for all 5 subjects
get_event_status() {
    local label="$1"
    local status=$(oc_query "
        SELECT se.subject_event_status_id 
        FROM study_event se 
        JOIN study_subject ss ON se.study_subject_id = ss.study_subject_id 
        WHERE ss.label = '$label' 
        AND ss.study_id = $DM_STUDY_ID 
        AND se.study_event_definition_id = $BASELINE_SED_ID 
        LIMIT 1
    ")
    echo "${status:-0}"
}

STATUS_101=$(get_event_status "DM-101")
STATUS_102=$(get_event_status "DM-102")
STATUS_103=$(get_event_status "DM-103")
STATUS_104=$(get_event_status "DM-104")
STATUS_105=$(get_event_status "DM-105")

echo "Final Statuses:"
echo "DM-101: $STATUS_101"
echo "DM-102: $STATUS_102"
echo "DM-103: $STATUS_103"
echo "DM-104: $STATUS_104"
echo "DM-105: $STATUS_105"

# Audit log interactions check
AUDIT_LOG_COUNT=$(get_recent_audit_count 60)
AUDIT_BASELINE_COUNT=$(cat /tmp/audit_baseline_count 2>/dev/null || echo "0")

# Write to JSON
TEMP_JSON=$(mktemp /tmp/reconcile_statuses_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "result_nonce": "$(cat /tmp/result_nonce 2>/dev/null)",
    "dm101_status": $STATUS_101,
    "dm102_status": $STATUS_102,
    "dm103_status": $STATUS_103,
    "dm104_status": $STATUS_104,
    "dm105_status": $STATUS_105,
    "audit_log_count": ${AUDIT_LOG_COUNT:-0},
    "audit_baseline_count": ${AUDIT_BASELINE_COUNT:-0},
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move temp file to final destination safely
rm -f /tmp/reconcile_statuses_result.json 2>/dev/null || sudo rm -f /tmp/reconcile_statuses_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/reconcile_statuses_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/reconcile_statuses_result.json
chmod 666 /tmp/reconcile_statuses_result.json 2>/dev/null || sudo chmod 666 /tmp/reconcile_statuses_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "JSON result exported to /tmp/reconcile_statuses_result.json"
echo "=== Export Complete ==="