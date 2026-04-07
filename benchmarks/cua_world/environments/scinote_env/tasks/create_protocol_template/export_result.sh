#!/bin/bash
echo "=== Exporting create_protocol_template result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

INITIAL_COUNT=$(cat /tmp/initial_repo_proto_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM protocols WHERE my_module_id IS NULL;" | tr -d '[:space:]')

# Search for the expected protocol in the repository
EXPECTED_NAME="Western Blot Protocol"
PROTO_DATA=$(scinote_db_query "SELECT id, name, description, created_at FROM protocols WHERE my_module_id IS NULL AND LOWER(TRIM(name)) = LOWER(TRIM('${EXPECTED_NAME}')) ORDER BY created_at DESC LIMIT 1;")

PROTO_FOUND="false"
PROTO_ID=""
PROTO_NAME=""
PROTO_DESC=""
PROTO_CREATED=""
STEPS_JSON="[]"
STEP_COUNT="0"

if [ -n "$PROTO_DATA" ]; then
    PROTO_FOUND="true"
    PROTO_ID=$(echo "$PROTO_DATA" | cut -d'|' -f1)
    PROTO_NAME=$(echo "$PROTO_DATA" | cut -d'|' -f2)
    PROTO_DESC=$(echo "$PROTO_DATA" | cut -d'|' -f3)
    PROTO_CREATED=$(echo "$PROTO_DATA" | cut -d'|' -f4)
    
    # Get steps for this protocol
    STEP_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM steps WHERE protocol_id=${PROTO_ID};" | tr -d '[:space:]')
    STEPS_DATA=$(scinote_db_query "SELECT id, name, position FROM steps WHERE protocol_id=${PROTO_ID} ORDER BY position;")
    
    STEPS_JSON="["
    FIRST=true
    while IFS='|' read -r step_id step_name step_position; do
        [ -z "$step_id" ] && continue
        
        step_name_clean=$(json_escape "$step_name")
        
        # Get text content for this step
        STEP_TEXT=$(scinote_db_query "SELECT text FROM step_texts WHERE step_id=${step_id} LIMIT 1;" 2>/dev/null | head -1)
        STEP_TEXT_CLEAN=$(json_escape "$STEP_TEXT")
        
        if [ "$FIRST" = true ]; then
            FIRST=false
        else
            STEPS_JSON="${STEPS_JSON}, "
        fi
        STEPS_JSON="${STEPS_JSON}{\"id\": \"${step_id}\", \"name\": \"${step_name_clean}\", \"position\": ${step_position:-0}, \"text_content\": \"${STEP_TEXT_CLEAN}\"}"
    done <<< "$STEPS_DATA"
    STEPS_JSON="${STEPS_JSON}]"
fi

# Escape fields
PROTO_NAME_ESCAPED=$(json_escape "$PROTO_NAME")
PROTO_DESC_ESCAPED=$(json_escape "$PROTO_DESC")

# Build the final JSON result
RESULT_JSON=$(cat << EOF
{
    "task_start_time": ${TASK_START},
    "task_end_time": ${TASK_END},
    "initial_repo_protocol_count": ${INITIAL_COUNT:-0},
    "current_repo_protocol_count": ${CURRENT_COUNT:-0},
    "protocol_found": ${PROTO_FOUND},
    "protocol": {
        "id": "${PROTO_ID}",
        "name": "${PROTO_NAME_ESCAPED}",
        "description": "${PROTO_DESC_ESCAPED}",
        "created_at": "${PROTO_CREATED}",
        "step_count": ${STEP_COUNT:-0},
        "steps": ${STEPS_JSON}
    },
    "screenshot_path": "/tmp/task_end_screenshot.png"
}
EOF
)

safe_write_json "/tmp/create_protocol_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/create_protocol_result.json"
cat /tmp/create_protocol_result.json
echo "=== Export complete ==="