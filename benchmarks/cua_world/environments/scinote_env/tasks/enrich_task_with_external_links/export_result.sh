#!/bin/bash
echo "=== Exporting enrich_task_with_external_links result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

TASK_ID=$(cat /tmp/task_module_id 2>/dev/null || echo "0")
INITIAL_UPDATED_AT=$(cat /tmp/initial_task_updated_at 2>/dev/null || echo "0")
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# If task_id isn't cached, look it up
if [ "$TASK_ID" = "0" ] || [ -z "$TASK_ID" ]; then
    TASK_ID=$(scinote_db_query "SELECT mm.id FROM my_modules mm JOIN experiments e ON mm.experiment_id = e.id JOIN projects p ON e.project_id = p.id WHERE mm.name='Cas9 RNP Preparation' AND e.name='In vitro Cleavage' AND p.name='CRISPR Assay Development' LIMIT 1;" | tr -d '[:space:]')
fi

# Guard: if we still don't have a task ID, write a minimal valid JSON and exit
if [ -z "$TASK_ID" ]; then
    RESULT_JSON='{"task_found":false,"description":"","initial_updated_at":0,"current_updated_at":0,"task_start_time":0,"export_timestamp":"'"$(date -Iseconds)"'"}'
    safe_write_json "/tmp/enrich_task_result.json" "$RESULT_JSON"
    echo "No task found. Result saved."
    exit 0
fi

# Fetch the current description and timestamp
TASK_DATA=$(scinote_db_query "SELECT description, extract(epoch from updated_at) FROM my_modules WHERE id=${TASK_ID};")

DESCRIPTION=""
CURRENT_UPDATED_AT="0"

if [ -n "$TASK_DATA" ]; then
    # Parse the output
    DESCRIPTION=$(echo "$TASK_DATA" | cut -d'|' -f1)
    # The epoch time might have decimal points, truncate them
    CURRENT_UPDATED_AT=$(echo "$TASK_DATA" | cut -d'|' -f2 | tr -d '[:space:]' | cut -d'.' -f1)
    
    # If DESCRIPTION is purely empty or NULL
    if [ "$DESCRIPTION" = "NULL" ] || [ -z "$DESCRIPTION" ]; then
        DESCRIPTION=""
    fi
fi

# Escape description for JSON
DESCRIPTION_ESCAPED=$(json_escape "$DESCRIPTION")

RESULT_JSON=$(cat << EOF
{
    "task_found": true,
    "task_id": "${TASK_ID}",
    "description": "${DESCRIPTION_ESCAPED}",
    "initial_updated_at": ${INITIAL_UPDATED_AT:-0},
    "current_updated_at": ${CURRENT_UPDATED_AT:-0},
    "task_start_time": ${TASK_START_TIME:-0},
    "export_timestamp": "$(date -Iseconds)"
}
EOF
)

safe_write_json "/tmp/enrich_task_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/enrich_task_result.json"
echo "Description length: ${#DESCRIPTION} chars"
echo "=== Export complete ==="