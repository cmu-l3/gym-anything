#!/bin/bash
echo "=== Exporting create_bolo_person result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get initial state info
INITIAL_BOLO_COUNT=$(cat /tmp/initial_bolo_count 2>/dev/null || echo "0")
CURRENT_BOLO_COUNT=$(get_bolo_person_count)

# Read baseline max ID to filter out pre-existing seed data
BASELINE_MAX_BOLO=$(cat /tmp/baseline_max_bolo_id 2>/dev/null | tr -cd '0-9' || echo "0")
BASELINE_MAX_BOLO=${BASELINE_MAX_BOLO:-0}

# Initialize variables
BOLO_FOUND="false"
BOLO_ID=""
BOLO_FNAME=""
BOLO_LNAME=""
BOLO_SEX=""
BOLO_RACE=""
BOLO_HEIGHT=""
BOLO_WEIGHT=""
BOLO_HAIR=""
BOLO_DESC=""
BOLO_LAST_SEEN=""

# Search logic:
# 1. Look for exact name match created after the task started (ID > BASELINE)
BOLO_ID=$(opencad_db_query "SELECT id FROM bolos_persons WHERE LOWER(first_name) LIKE '%marcus%' AND LOWER(last_name) LIKE '%holloway%' AND id > ${BASELINE_MAX_BOLO} ORDER BY id DESC LIMIT 1")

# 2. If not found, look for partial match (First name only)
if [ -z "$BOLO_ID" ]; then
    BOLO_ID=$(opencad_db_query "SELECT id FROM bolos_persons WHERE LOWER(first_name) LIKE '%marcus%' AND id > ${BASELINE_MAX_BOLO} ORDER BY id DESC LIMIT 1")
fi

# 3. If not found, look for last name only
if [ -z "$BOLO_ID" ]; then
    BOLO_ID=$(opencad_db_query "SELECT id FROM bolos_persons WHERE LOWER(last_name) LIKE '%holloway%' AND id > ${BASELINE_MAX_BOLO} ORDER BY id DESC LIMIT 1")
fi

# 4. Fallback: Get the most recent BOLO person created (if count increased)
if [ -z "$BOLO_ID" ] && [ "$CURRENT_BOLO_COUNT" -gt "$INITIAL_BOLO_COUNT" ]; then
    BOLO_ID=$(opencad_db_query "SELECT id FROM bolos_persons WHERE id > ${BASELINE_MAX_BOLO} ORDER BY id DESC LIMIT 1")
fi

if [ -n "$BOLO_ID" ]; then
    BOLO_FOUND="true"
    # Extract details
    # Note: Column names based on standard OpenCAD schema.
    # We concat multiple description fields (notes, misc_description) just in case the agent used different fields.
    BOLO_FNAME=$(opencad_db_query "SELECT first_name FROM bolos_persons WHERE id=${BOLO_ID}")
    BOLO_LNAME=$(opencad_db_query "SELECT last_name FROM bolos_persons WHERE id=${BOLO_ID}")
    BOLO_SEX=$(opencad_db_query "SELECT sex FROM bolos_persons WHERE id=${BOLO_ID}")
    BOLO_RACE=$(opencad_db_query "SELECT race FROM bolos_persons WHERE id=${BOLO_ID}")
    BOLO_HEIGHT=$(opencad_db_query "SELECT height FROM bolos_persons WHERE id=${BOLO_ID}")
    BOLO_WEIGHT=$(opencad_db_query "SELECT weight FROM bolos_persons WHERE id=${BOLO_ID}")
    BOLO_HAIR=$(opencad_db_query "SELECT hair_color FROM bolos_persons WHERE id=${BOLO_ID}")
    BOLO_LAST_SEEN=$(opencad_db_query "SELECT last_seen FROM bolos_persons WHERE id=${BOLO_ID}")
    
    # Concatenate description fields (misc_description, other markers etc)
    # Using CONCAT_WS to join potential description columns
    BOLO_DESC=$(opencad_db_query "SELECT CONCAT_WS(' ', misc_description, tattoos, build) FROM bolos_persons WHERE id=${BOLO_ID}")
fi

# Create JSON result
# Using safe_write_result to handle permissions
RESULT_JSON=$(cat << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_bolo_count": ${INITIAL_BOLO_COUNT:-0},
    "current_bolo_count": ${CURRENT_BOLO_COUNT:-0},
    "bolo_found": ${BOLO_FOUND},
    "bolo": {
        "id": "$(json_escape "${BOLO_ID}")",
        "first_name": "$(json_escape "${BOLO_FNAME}")",
        "last_name": "$(json_escape "${BOLO_LNAME}")",
        "sex": "$(json_escape "${BOLO_SEX}")",
        "race": "$(json_escape "${BOLO_RACE}")",
        "height": "$(json_escape "${BOLO_HEIGHT}")",
        "weight": "$(json_escape "${BOLO_WEIGHT}")",
        "hair_color": "$(json_escape "${BOLO_HAIR}")",
        "description_combined": "$(json_escape "${BOLO_DESC}")",
        "last_seen": "$(json_escape "${BOLO_LAST_SEEN}")"
    }
}
EOF
)

safe_write_result "$RESULT_JSON" /tmp/create_bolo_person_result.json

echo "Result saved to /tmp/create_bolo_person_result.json"
cat /tmp/create_bolo_person_result.json
echo "=== Export complete ==="