#!/bin/bash
echo "=== Exporting import_clinical_data result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Resolve basic contextual IDs
DM_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' AND status_id != 3 LIMIT 1")
DM101_SS_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = 'DM-101' AND study_id = $DM_STUDY_ID LIMIT 1")
EVENT_DEF_ID=$(oc_query "SELECT study_event_definition_id FROM study_event_definition WHERE name = 'Baseline Assessment' AND study_id = $DM_STUDY_ID AND status_id != 3 LIMIT 1")

# Extract the event_crf ID if it was created during import
EVENT_CRF_DATA=$(oc_query "
    SELECT ec.event_crf_id, ec.status_id 
    FROM event_crf ec 
    JOIN study_event se ON ec.study_event_id = se.study_event_id 
    JOIN crf_version cv ON ec.crf_version_id = cv.crf_version_id
    JOIN crf c ON cv.crf_id = c.crf_id
    WHERE se.study_subject_id = $DM101_SS_ID 
      AND se.study_event_definition_id = $EVENT_DEF_ID 
      AND c.oc_oid = 'F_DEMOGRAPHICS'
    LIMIT 1
")

EVENT_CRF_ID=""
EVENT_CRF_STATUS=""
EVENT_CRF_EXISTS="false"

if [ -n "$EVENT_CRF_DATA" ]; then
    EVENT_CRF_EXISTS="true"
    EVENT_CRF_ID=$(echo "$EVENT_CRF_DATA" | cut -d'|' -f1)
    EVENT_CRF_STATUS=$(echo "$EVENT_CRF_DATA" | cut -d'|' -f2)
    echo "Found event_crf_id: $EVENT_CRF_ID (Status: $EVENT_CRF_STATUS)"
else
    echo "No event_crf found for DM-101 Demographics Survey Baseline Assessment"
fi

# Extract imported values from item_data
echo "Querying item_data values..."
ITEM_DATA_EXPORT="{}"

if [ "$EVENT_CRF_EXISTS" = "true" ]; then
    RAW_ITEM_DATA=$(oc_query "
        SELECT i.oc_oid, id.value
        FROM item_data id
        JOIN item i ON id.item_id = i.item_id
        WHERE id.event_crf_id = $EVENT_CRF_ID AND id.status_id != 3
    ")
    
    # Manually format rows into JSON key-value pairs
    if [ -n "$RAW_ITEM_DATA" ]; then
        JSON_PAIRS=""
        while IFS='|' read -r OID VAL; do
            # Trim and escape
            OID=$(echo "$OID" | xargs)
            VAL=$(echo "$VAL" | sed 's/"/\\"/g' | xargs)
            if [ -n "$JSON_PAIRS" ]; then
                JSON_PAIRS="$JSON_PAIRS, "
            fi
            JSON_PAIRS="$JSON_PAIRS\"$OID\": \"$VAL\""
        done <<< "$RAW_ITEM_DATA"
        
        ITEM_DATA_EXPORT="{ $JSON_PAIRS }"
    fi
fi

echo "Extracted Items: $ITEM_DATA_EXPORT"

# Get item_data row count specific to this event_crf
EVENT_ITEM_COUNT="0"
if [ "$EVENT_CRF_EXISTS" = "true" ]; then
    EVENT_ITEM_COUNT=$(oc_query "SELECT COUNT(*) FROM item_data WHERE event_crf_id = $EVENT_CRF_ID AND status_id != 3")
fi

# Compare total item_data count to baseline
INITIAL_ITEM_DATA_COUNT=$(cat /tmp/initial_item_data_count 2>/dev/null || echo "0")
CURRENT_ITEM_DATA_COUNT=$(oc_query "SELECT COUNT(*) FROM item_data")

# Get audit logs to verify GUI use instead of direct SQL insertion
AUDIT_BASELINE=$(cat /tmp/audit_baseline_count 2>/dev/null || echo "0")
AUDIT_CURRENT=$(get_recent_audit_count 60)

# Build the JSON file
TEMP_JSON=$(mktemp /tmp/import_data_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "event_crf_exists": $EVENT_CRF_EXISTS,
    "event_crf_status_id": "${EVENT_CRF_STATUS:-0}",
    "event_item_data_count": ${EVENT_ITEM_COUNT:-0},
    "imported_values": $ITEM_DATA_EXPORT,
    "initial_db_item_count": $INITIAL_ITEM_DATA_COUNT,
    "current_db_item_count": $CURRENT_ITEM_DATA_COUNT,
    "audit_baseline_count": $AUDIT_BASELINE,
    "audit_current_count": $AUDIT_CURRENT,
    "result_nonce": "$(cat /tmp/result_nonce 2>/dev/null || echo '')",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location safely
rm -f /tmp/import_clinical_data_result.json 2>/dev/null || sudo rm -f /tmp/import_clinical_data_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/import_clinical_data_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/import_clinical_data_result.json
chmod 666 /tmp/import_clinical_data_result.json 2>/dev/null || sudo chmod 666 /tmp/import_clinical_data_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "JSON payload saved:"
cat /tmp/import_clinical_data_result.json

echo "=== Export complete ==="