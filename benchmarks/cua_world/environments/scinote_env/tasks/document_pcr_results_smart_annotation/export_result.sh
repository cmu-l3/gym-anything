#!/bin/bash
echo "=== Exporting document_pcr_results_smart_annotation result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

take_screenshot /tmp/task_end_screenshot.png

INITIAL_COUNT=$(cat /tmp/initial_result_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM results;" | tr -d '[:space:]')

# Retrieve the target Task ID
TASK_ID=$(scinote_db_query "SELECT id FROM my_modules WHERE name='PCR Validation' LIMIT 1;" | tr -d '[:space:]')

TASK_RESULT_COUNT="0"
ASSET_COUNT="0"
TABLE_COUNT="0"
TEXT_COUNT="0"
FILE_MATCH="false"
RICH_TEXT=""
TABLE_DATA_TEXT=""

if [ -n "$TASK_ID" ]; then
    # Count results specifically created for this task
    TASK_RESULT_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM results WHERE my_module_id=${TASK_ID};" | tr -d '[:space:]')
    ASSET_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM results WHERE my_module_id=${TASK_ID} AND type='ResultAsset';" | tr -d '[:space:]')
    TABLE_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM results WHERE my_module_id=${TASK_ID} AND type='ResultTable';" | tr -d '[:space:]')
    TEXT_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM results WHERE my_module_id=${TASK_ID} AND type='ResultText';" | tr -d '[:space:]')
    
    # Check if the specific gel image file was uploaded correctly (ActiveStorage reference)
    FILE_MATCH_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM active_storage_blobs b JOIN active_storage_attachments a ON b.id = a.blob_id JOIN results r ON a.record_id = r.id WHERE r.my_module_id=${TASK_ID} AND a.record_type='Result' AND b.filename='gel_electrophoresis.jpg';" | tr -d '[:space:]')
    if [ "${FILE_MATCH_COUNT:-0}" -gt 0 ]; then
        FILE_MATCH="true"
    fi
    
    # Extract rich text for smart annotation checking (checks Rails ActionText table first)
    RICH_TEXT=$(scinote_db_query "SELECT body FROM action_text_rich_texts WHERE record_type='Result' AND record_id IN (SELECT id FROM results WHERE my_module_id=${TASK_ID} AND type='ResultText');" 2>/dev/null | head -c 2000 | json_escape)
    
    # Fallback for older SciNote versions
    if [ -z "$RICH_TEXT" ] || [ "$RICH_TEXT" = " " ]; then
        RICH_TEXT=$(scinote_db_query "SELECT text FROM result_texts WHERE result_id IN (SELECT id FROM results WHERE my_module_id=${TASK_ID} AND type='ResultText');" 2>/dev/null | head -c 2000 | json_escape)
    fi
    
    # Extract table data text for value verification
    TABLE_DATA_TEXT=$(scinote_db_query "SELECT value FROM result_cells rc JOIN result_rows rr ON rc.result_row_id = rr.id JOIN results r ON rr.result_id = r.id WHERE r.my_module_id=${TASK_ID};" 2>/dev/null | tr '\n' ' ' | json_escape)
    
    # Fallbacks for different schema variants of table storage
    if [ -z "$TABLE_DATA_TEXT" ] || [ "$TABLE_DATA_TEXT" = " " ]; then
        TABLE_DATA_TEXT=$(scinote_db_query "SELECT content FROM result_tables WHERE result_id IN (SELECT id FROM results WHERE my_module_id=${TASK_ID} AND type='ResultTable');" 2>/dev/null | tr '\n' ' ' | json_escape)
    fi
    if [ -z "$TABLE_DATA_TEXT" ] || [ "$TABLE_DATA_TEXT" = " " ]; then
        TABLE_DATA_TEXT=$(scinote_db_query "SELECT data FROM results WHERE my_module_id=${TASK_ID} AND type='ResultTable';" 2>/dev/null | tr '\n' ' ' | json_escape)
    fi
fi

# Build JSON Export
RESULT_JSON=$(cat << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_total_results": ${INITIAL_COUNT:-0},
    "current_total_results": ${CURRENT_COUNT:-0},
    "task_id": "${TASK_ID}",
    "task_result_count": ${TASK_RESULT_COUNT:-0},
    "asset_count": ${ASSET_COUNT:-0},
    "table_count": ${TABLE_COUNT:-0},
    "text_count": ${TEXT_COUNT:-0},
    "file_uploaded": ${FILE_MATCH},
    "rich_text": "${RICH_TEXT}",
    "table_data": "${TABLE_DATA_TEXT}",
    "export_timestamp": "$(date -Iseconds)"
}
EOF
)

safe_write_json "/tmp/document_pcr_results.json" "$RESULT_JSON"

echo "Result saved to /tmp/document_pcr_results.json"
cat /tmp/document_pcr_results.json
echo "=== Export complete ==="