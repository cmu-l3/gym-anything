#!/bin/bash
echo "=== Exporting link_inventory_to_protocol result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get IDs and timestamps
STEP_ID=$(cat /tmp/step_id 2>/dev/null || echo "0")
ROW_ID=$(cat /tmp/row_id 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Query for an explicit exact database link
# Different versions of SciNote might name this table slightly differently, so we check a few common known schemas.
HAS_EXACT_LINK="false"
LINK_TABLE="none"
for table in step_repository_rows repository_row_steps step_materials step_assets step_items; do
    COUNT=$(scinote_db_query "SELECT COUNT(*) FROM ${table} WHERE step_id=${STEP_ID} AND repository_row_id=${ROW_ID};" 2>/dev/null | tr -d '[:space:]')
    if [ "${COUNT:-0}" -gt 0 ] 2>/dev/null; then
        HAS_EXACT_LINK="true"
        LINK_TABLE="${table}"
        break
    fi
done

# 2. Check if ANY item was linked to the step (in case they picked the wrong item)
ANY_LINK_COUNT=0
if [ "$HAS_EXACT_LINK" = "false" ]; then
    for table in step_repository_rows repository_row_steps step_materials step_assets step_items; do
        COUNT=$(scinote_db_query "SELECT COUNT(*) FROM ${table} WHERE step_id=${STEP_ID};" 2>/dev/null | tr -d '[:space:]')
        if [ "${COUNT:-0}" -gt 0 ] 2>/dev/null; then
            ANY_LINK_COUNT=${COUNT}
            LINK_TABLE="${table}"
            break
        fi
    done
fi

# 3. Check if the Step's `updated_at` changed during the task
STEP_UPDATED_EPOCH=$(scinote_db_query "SELECT EXTRACT(EPOCH FROM updated_at) FROM steps WHERE id=${STEP_ID};" 2>/dev/null | tr -d '[:space:]' | cut -d. -f1)
STEP_MODIFIED="false"
if [ "${STEP_UPDATED_EPOCH:-0}" -gt "$TASK_START" ] 2>/dev/null; then
    STEP_MODIFIED="true"
fi

# 4. Check if the protocol or module got renamed/deleted (Integrity check)
STEP_STILL_EXISTS=$(scinote_db_query "SELECT COUNT(*) FROM steps WHERE id=${STEP_ID};" 2>/dev/null | tr -d '[:space:]')

# Build the JSON output safely
RESULT_JSON=$(cat << EOF
{
    "task_start": ${TASK_START},
    "task_end": ${TASK_END},
    "step_id": ${STEP_ID},
    "row_id": ${ROW_ID},
    "has_exact_link": ${HAS_EXACT_LINK},
    "link_table_found": "${LINK_TABLE}",
    "any_link_count": ${ANY_LINK_COUNT},
    "step_modified_during_task": ${STEP_MODIFIED},
    "step_still_exists": $(if [ "${STEP_STILL_EXISTS:-0}" -eq 1 ]; then echo "true"; else echo "false"; fi)
}
EOF
)

safe_write_json "/tmp/link_inventory_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/link_inventory_result.json"
cat /tmp/link_inventory_result.json
echo "=== Export complete ==="