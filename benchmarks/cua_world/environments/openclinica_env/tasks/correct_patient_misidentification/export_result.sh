#!/bin/bash
echo "=== Exporting correct_patient_misidentification result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Resolve IDs
DM_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' AND status_id != 3 LIMIT 1")
WEEK4_SED_ID=$(oc_query "SELECT study_event_definition_id FROM study_event_definition WHERE name = 'Week 4 Follow-up' AND study_id = $DM_STUDY_ID AND status_id != 3 LIMIT 1")
DM101_SS_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = 'DM-101' AND study_id = $DM_STUDY_ID AND status_id != 3 LIMIT 1")
DM102_SS_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = 'DM-102' AND study_id = $DM_STUDY_ID AND status_id != 3 LIMIT 1")

# --- 1. Check DM-101 Event Status (Should be Removed) ---
DM101_EVENT_DATA=$(oc_query "SELECT study_event_id, status_id FROM study_event WHERE study_subject_id = $DM101_SS_ID AND study_event_definition_id = $WEEK4_SED_ID ORDER BY study_event_id DESC LIMIT 1" 2>/dev/null)
DM101_EVENT_ID=""
DM101_STATUS_ID="0" # 0 means not found/deleted
if [ -n "$DM101_EVENT_DATA" ]; then
    DM101_EVENT_ID=$(echo "$DM101_EVENT_DATA" | cut -d'|' -f1)
    DM101_STATUS_ID=$(echo "$DM101_EVENT_DATA" | cut -d'|' -f2)
fi
echo "DM-101 Event status_id: $DM101_STATUS_ID (Expected 5 or 7, or missing=0)"

# --- 2. Check DM-102 Event Status (Should be Active/Scheduled/Completed) ---
DM102_EVENT_DATA=$(oc_query "SELECT study_event_id, status_id FROM study_event WHERE study_subject_id = $DM102_SS_ID AND study_event_definition_id = $WEEK4_SED_ID AND status_id != 5 AND status_id != 7 ORDER BY study_event_id DESC LIMIT 1" 2>/dev/null)
DM102_EVENT_EXISTS="false"
DM102_EVENT_ID=""
if [ -n "$DM102_EVENT_DATA" ]; then
    DM102_EVENT_EXISTS="true"
    DM102_EVENT_ID=$(echo "$DM102_EVENT_DATA" | cut -d'|' -f1)
fi
echo "DM-102 Event Exists: $DM102_EVENT_EXISTS (ID: $DM102_EVENT_ID)"

# --- 3. Extract Item Data for DM-102 ---
DM102_VALUES=""
if [ "$DM102_EVENT_EXISTS" = "true" ]; then
    # Query all item data values associated with DM-102's Week 4 Follow-up event
    RAW_VALUES=$(oc_query "SELECT id.value FROM item_data id JOIN event_crf ec ON id.event_crf_id = ec.event_crf_id WHERE ec.study_event_id = $DM102_EVENT_ID AND id.status_id != 5 AND id.status_id != 7" 2>/dev/null)
    
    # Format the values into a pipe-separated string
    if [ -n "$RAW_VALUES" ]; then
        DM102_VALUES=$(echo "$RAW_VALUES" | tr '\n' '|' | sed 's/|$//')
    fi
fi
echo "DM-102 Entered Values: $DM102_VALUES"

# --- 4. Get Audit Log Count ---
AUDIT_LOG_COUNT=$(get_recent_audit_count 60)
AUDIT_BASELINE_COUNT=$(cat /tmp/audit_baseline_count 2>/dev/null || echo "0")

# --- 5. Write Result JSON ---
NONCE=$(cat /tmp/result_nonce 2>/dev/null || echo "")

TEMP_JSON=$(mktemp /tmp/correct_patient_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "dm101_status_id": ${DM101_STATUS_ID:-0},
    "dm102_event_exists": $DM102_EVENT_EXISTS,
    "dm102_values": "$(json_escape "${DM102_VALUES:-}")",
    "audit_log_count": ${AUDIT_LOG_COUNT:-0},
    "audit_baseline_count": ${AUDIT_BASELINE_COUNT:-0},
    "result_nonce": "$NONCE"
}
EOF

rm -f /tmp/correct_patient_misidentification_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/correct_patient_misidentification_result.json
chmod 666 /tmp/correct_patient_misidentification_result.json
rm -f "$TEMP_JSON"

echo "Result JSON saved."
cat /tmp/correct_patient_misidentification_result.json
echo "=== Export Complete ==="