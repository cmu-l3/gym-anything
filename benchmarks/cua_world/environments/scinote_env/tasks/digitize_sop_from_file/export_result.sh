#!/bin/bash
echo "=== Exporting digitize_sop_from_file result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_protocol_count.txt 2>/dev/null || echo "0")
CURRENT_COUNT=$(get_protocol_count)

# Search for the expected protocol created during the task window
EXPECTED_NAME="RIPA Lysis Protocol"
PROTO_DATA=$(scinote_db_query "SELECT id, name, extract(epoch from created_at) FROM protocols WHERE LOWER(TRIM(name)) = LOWER(TRIM('${EXPECTED_NAME}')) ORDER BY created_at DESC LIMIT 1;")

PROTO_FOUND="false"
PROTO_ID=""
PROTO_NAME=""
PROTO_CREATED_AT="0"

if [ -n "$PROTO_DATA" ]; then
    PROTO_FOUND="true"
    PROTO_ID=$(echo "$PROTO_DATA" | cut -d'|' -f1)
    PROTO_NAME=$(echo "$PROTO_DATA" | cut -d'|' -f2)
    PROTO_CREATED_AT=$(echo "$PROTO_DATA" | cut -d'|' -f3 | cut -d'.' -f1) # remove decimal seconds
fi

# Fetch steps if protocol is found
STEPS_JSON="[]"
CURRENT_STEP_COUNT=0

if [ "$PROTO_FOUND" = "true" ] && [ -n "$PROTO_ID" ]; then
    CURRENT_STEP_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM steps WHERE protocol_id=${PROTO_ID};" | tr -d '[:space:]')
    STEPS_DATA=$(scinote_db_query "SELECT id, name, position FROM steps WHERE protocol_id=${PROTO_ID} ORDER BY position;")
    
    if [ -n "$STEPS_DATA" ]; then
        STEPS_JSON="["
        FIRST=true
        while IFS='|' read -r step_id step_name step_position; do
            [ -z "$step_id" ] && continue
            
            # Clean text using json_escape
            step_name_clean=$(json_escape "$step_name")
            
            # Extract rich text description for the step
            STEP_TEXT=$(scinote_db_query "SELECT st.text FROM step_texts st JOIN step_orderable_elements soe ON soe.orderable_type='StepText' AND soe.orderable_id=st.id WHERE soe.step_id=${step_id} LIMIT 1;" 2>/dev/null | head -1)
            if [ -z "$STEP_TEXT" ]; then
                STEP_TEXT=$(scinote_db_query "SELECT text FROM step_texts WHERE step_id=${step_id} LIMIT 1;" 2>/dev/null | head -1)
            fi
            
            # Remove HTML tags and escape
            STEP_TEXT_PLAIN=$(echo "$STEP_TEXT" | sed -e 's/<[^>]*>//g' | sed 's/&nbsp;/ /g' | xargs)
            STEP_TEXT_CLEAN=$(json_escape "$STEP_TEXT_PLAIN")

            if [ "$FIRST" = true ]; then
                FIRST=false
            else
                STEPS_JSON="${STEPS_JSON}, "
            fi
            STEPS_JSON="${STEPS_JSON}{\"id\": \"${step_id}\", \"name\": \"${step_name_clean}\", \"position\": ${step_position:-0}, \"text_content\": \"${STEP_TEXT_CLEAN}\"}"
        done <<< "$STEPS_DATA"
        STEPS_JSON="${STEPS_JSON}]"
    fi
fi

PROTO_NAME_ESCAPED=$(json_escape "$PROTO_NAME")

# Build final JSON
RESULT_JSON=$(cat << EOF
{
    "task_start_time": ${TASK_START_TIME},
    "initial_protocol_count": ${INITIAL_COUNT},
    "current_protocol_count": ${CURRENT_COUNT},
    "protocol_found": ${PROTO_FOUND},
    "protocol": {
        "id": "${PROTO_ID}",
        "name": "${PROTO_NAME_ESCAPED}",
        "created_at_epoch": ${PROTO_CREATED_AT:-0}
    },
    "step_count": ${CURRENT_STEP_COUNT:-0},
    "steps": ${STEPS_JSON},
    "export_timestamp": "$(date -Iseconds)"
}
EOF
)

safe_write_json "/tmp/digitize_sop_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/digitize_sop_result.json"
cat /tmp/digitize_sop_result.json
echo "=== Export complete ==="