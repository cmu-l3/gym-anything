#!/bin/bash
echo "=== Exporting remediate_misallocated_clinical_data result ==="

source /workspace/scripts/task_utils.sh

# Final screenshot
take_screenshot /tmp/task_end_screenshot.png

DM_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' LIMIT 1")
DM102_SS_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = 'DM-102' AND study_id = $DM_STUDY_ID LIMIT 1")
DM103_SS_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = 'DM-103' AND study_id = $DM_STUDY_ID LIMIT 1")
WEEK4_SED_ID=$(oc_query "SELECT study_event_definition_id FROM study_event_definition WHERE name = 'Week 4 Follow-up' AND study_id = $DM_STUDY_ID LIMIT 1")

# --- 1. Evaluate DM-103 (Should be Removed) ---
DM103_EVENT_EXISTS="false"
DM103_STATUS_ID="0"
DM103_SUBJECT_EVENT_STATUS_ID="0"

DM103_EVENT_DATA=$(oc_query "SELECT status_id, subject_event_status_id FROM study_event WHERE study_subject_id = $DM103_SS_ID AND study_event_definition_id = $WEEK4_SED_ID ORDER BY study_event_id DESC LIMIT 1")

if [ -n "$DM103_EVENT_DATA" ]; then
    DM103_EVENT_EXISTS="true"
    DM103_STATUS_ID=$(echo "$DM103_EVENT_DATA" | cut -d'|' -f1)
    DM103_SUBJECT_EVENT_STATUS_ID=$(echo "$DM103_EVENT_DATA" | cut -d'|' -f2)
fi
echo "DM-103 Event: exists=$DM103_EVENT_EXISTS, row_status=$DM103_STATUS_ID, event_status=$DM103_SUBJECT_EVENT_STATUS_ID"

# --- 2. Evaluate DM-102 (Should be Scheduled/Entered) ---
DM102_EVENT_EXISTS="false"
DM102_START_DATE=""
DM102_EVENT_ID=""
DM102_ITEM_VALUES=""

DM102_EVENT_DATA=$(oc_query "SELECT study_event_id, start_date FROM study_event WHERE study_subject_id = $DM102_SS_ID AND study_event_definition_id = $WEEK4_SED_ID AND status_id != 5 AND status_id != 7 ORDER BY study_event_id DESC LIMIT 1")

if [ -n "$DM102_EVENT_DATA" ]; then
    DM102_EVENT_EXISTS="true"
    DM102_EVENT_ID=$(echo "$DM102_EVENT_DATA" | cut -d'|' -f1)
    DM102_START_DATE=$(echo "$DM102_EVENT_DATA" | cut -d'|' -f2)
    
    # Extract item data values entered for this event
    DM102_ITEM_VALUES=$(oc_query "SELECT value FROM item_data id JOIN event_crf ec ON id.event_crf_id = ec.event_crf_id WHERE ec.study_event_id = $DM102_EVENT_ID AND id.status_id != 5 AND id.status_id != 7")
fi
echo "DM-102 Event: exists=$DM102_EVENT_EXISTS, date=$DM102_START_DATE"
echo "DM-102 Item Values: "
echo "$DM102_ITEM_VALUES"

# Replace newlines with commas for clean JSON serialization
DM102_ITEM_VALUES_CLEAN=$(echo "$DM102_ITEM_VALUES" | tr '\n' ',' | sed 's/,$//')

# Audit logs
AUDIT_LOG_COUNT=$(get_recent_audit_count 60)
AUDIT_BASELINE_COUNT=$(cat /tmp/audit_baseline_count 2>/dev/null || echo "0")
NONCE=$(cat /tmp/result_nonce 2>/dev/null || echo "")

# Write JSON output
TEMP_JSON=$(mktemp /tmp/remediate_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "dm103_event_exists": $DM103_EVENT_EXISTS,
    "dm103_status_id": ${DM103_STATUS_ID:-0},
    "dm103_subject_event_status_id": ${DM103_SUBJECT_EVENT_STATUS_ID:-0},
    "dm102_event_exists": $DM102_EVENT_EXISTS,
    "dm102_start_date": "$(json_escape "${DM102_START_DATE:-}")",
    "dm102_item_values": "$(json_escape "${DM102_ITEM_VALUES_CLEAN:-}")",
    "audit_log_count": ${AUDIT_LOG_COUNT:-0},
    "audit_baseline_count": ${AUDIT_BASELINE_COUNT:-0},
    "result_nonce": "$NONCE"
}
EOF

rm -f /tmp/remediate_result.json 2>/dev/null || sudo rm -f /tmp/remediate_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/remediate_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/remediate_result.json
chmod 666 /tmp/remediate_result.json 2>/dev/null || sudo chmod 666 /tmp/remediate_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export complete ==="