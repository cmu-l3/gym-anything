#!/bin/bash
echo "=== Exporting add_protocol_steps result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

INITIAL_STEP_COUNT=$(cat /tmp/initial_step_count 2>/dev/null || echo "0")
TASK_ID=$(cat /tmp/task_module_id 2>/dev/null || echo "0")
PROTOCOL_ID=$(cat /tmp/protocol_id 2>/dev/null || echo "0")

# If IDs aren't cached, look them up
if [ "$PROTOCOL_ID" = "0" ] || [ -z "$PROTOCOL_ID" ]; then
    PROTOCOL_ID=$(scinote_db_query "SELECT p.id FROM protocols p JOIN my_modules mm ON p.my_module_id = mm.id WHERE mm.name='Enzyme Kinetics Assay' LIMIT 1;" | tr -d '[:space:]')
fi

# Current step count
CURRENT_STEP_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM steps WHERE protocol_id=${PROTOCOL_ID};" | tr -d '[:space:]')

# Get all steps for this protocol
STEPS_DATA=$(scinote_db_query "SELECT s.id, s.name, s.position FROM steps s WHERE s.protocol_id=${PROTOCOL_ID} ORDER BY s.position;")

# Build steps array
STEPS_JSON="["
FIRST=true
while IFS='|' read -r step_id step_name step_position; do
    [ -z "$step_id" ] && continue
    step_name_clean=$(echo "$step_name" | sed 's/"/\\"/g' | xargs)

    # Get text content for this step
    STEP_TEXT=$(scinote_db_query "SELECT st.text FROM step_texts st JOIN step_orderable_elements soe ON soe.orderable_type='StepText' AND soe.orderable_id=st.id WHERE soe.step_id=${step_id} LIMIT 1;" 2>/dev/null | head -1)
    # Fallback: direct step_texts query
    if [ -z "$STEP_TEXT" ]; then
        STEP_TEXT=$(scinote_db_query "SELECT text FROM step_texts WHERE step_id=${step_id} LIMIT 1;" 2>/dev/null | head -1)
    fi
    STEP_TEXT_CLEAN=$(echo "$STEP_TEXT" | sed 's/"/\\"/g' | head -c 500)

    # Get checklists for this step
    CHECKLIST_DATA=$(scinote_db_query "SELECT c.id, c.name FROM checklists c WHERE c.step_id=${step_id};" 2>/dev/null)
    CHECKLIST_NAME=""
    CHECKLIST_ITEM_COUNT=0
    CHECKLIST_ITEMS_JSON="[]"
    if [ -n "$CHECKLIST_DATA" ]; then
        CHECKLIST_ID=$(echo "$CHECKLIST_DATA" | cut -d'|' -f1 | head -1)
        CHECKLIST_NAME=$(echo "$CHECKLIST_DATA" | cut -d'|' -f2 | head -1 | sed 's/"/\\"/g' | xargs)
        CHECKLIST_ITEM_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM checklist_items WHERE checklist_id=${CHECKLIST_ID};" | tr -d '[:space:]')
        ITEMS_RAW=$(scinote_db_query "SELECT text FROM checklist_items WHERE checklist_id=${CHECKLIST_ID} ORDER BY position;")
        CHECKLIST_ITEMS_JSON="["
        ITEM_FIRST=true
        while IFS= read -r item_text; do
            [ -z "$item_text" ] && continue
            item_text_clean=$(echo "$item_text" | sed 's/"/\\"/g' | xargs)
            if [ "$ITEM_FIRST" = true ]; then
                CHECKLIST_ITEMS_JSON="${CHECKLIST_ITEMS_JSON}\"${item_text_clean}\""
                ITEM_FIRST=false
            else
                CHECKLIST_ITEMS_JSON="${CHECKLIST_ITEMS_JSON}, \"${item_text_clean}\""
            fi
        done <<< "$ITEMS_RAW"
        CHECKLIST_ITEMS_JSON="${CHECKLIST_ITEMS_JSON}]"
    fi

    if [ "$FIRST" = true ]; then
        FIRST=false
    else
        STEPS_JSON="${STEPS_JSON}, "
    fi
    STEPS_JSON="${STEPS_JSON}{\"id\": \"${step_id}\", \"name\": \"${step_name_clean}\", \"position\": ${step_position:-0}, \"text_content\": \"${STEP_TEXT_CLEAN}\", \"checklist_name\": \"${CHECKLIST_NAME}\", \"checklist_item_count\": ${CHECKLIST_ITEM_COUNT:-0}, \"checklist_items\": ${CHECKLIST_ITEMS_JSON}}"
done <<< "$STEPS_DATA"
STEPS_JSON="${STEPS_JSON}]"

RESULT_JSON=$(cat << EOF
{
    "protocol_id": "${PROTOCOL_ID}",
    "task_id": "${TASK_ID}",
    "initial_step_count": ${INITIAL_STEP_COUNT:-0},
    "current_step_count": ${CURRENT_STEP_COUNT:-0},
    "steps": ${STEPS_JSON},
    "export_timestamp": "$(date -Iseconds)"
}
EOF
)

safe_write_json "/tmp/add_protocol_steps_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/add_protocol_steps_result.json"
cat /tmp/add_protocol_steps_result.json
echo "=== Export complete ==="
