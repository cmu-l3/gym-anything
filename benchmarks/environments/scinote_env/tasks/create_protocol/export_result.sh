#!/bin/bash
echo "=== Exporting create_protocol result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

INITIAL_COUNT=$(cat /tmp/initial_protocol_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(get_protocol_count)

# Search for the expected protocol (repository protocols: type 2-7)
EXPECTED_NAME="Western Blot Analysis v2"
PROTOCOL_DATA=$(scinote_db_query "SELECT id, name, protocol_type, created_at FROM protocols WHERE LOWER(TRIM(name)) = LOWER(TRIM('${EXPECTED_NAME}')) AND protocol_type IN (2, 3, 4, 5, 6, 7) ORDER BY created_at DESC LIMIT 1;")

PROTOCOL_FOUND="false"
PROTOCOL_ID=""
PROTOCOL_NAME=""
PROTOCOL_TYPE=""
PROTOCOL_CREATED=""

if [ -n "$PROTOCOL_DATA" ]; then
    PROTOCOL_FOUND="true"
    PROTOCOL_ID=$(echo "$PROTOCOL_DATA" | cut -d'|' -f1)
    PROTOCOL_NAME=$(echo "$PROTOCOL_DATA" | cut -d'|' -f2)
    PROTOCOL_TYPE=$(echo "$PROTOCOL_DATA" | cut -d'|' -f3)
    PROTOCOL_CREATED=$(echo "$PROTOCOL_DATA" | cut -d'|' -f4)
fi

# Also check all protocol types (user may have created it as task-level protocol)
if [ "$PROTOCOL_FOUND" = "false" ]; then
    PROTOCOL_DATA_ALL=$(scinote_db_query "SELECT id, name, protocol_type, created_at FROM protocols WHERE LOWER(TRIM(name)) = LOWER(TRIM('${EXPECTED_NAME}')) ORDER BY created_at DESC LIMIT 1;")
    if [ -n "$PROTOCOL_DATA_ALL" ]; then
        PROTOCOL_FOUND="true"
        PROTOCOL_ID=$(echo "$PROTOCOL_DATA_ALL" | cut -d'|' -f1)
        PROTOCOL_NAME=$(echo "$PROTOCOL_DATA_ALL" | cut -d'|' -f2)
        PROTOCOL_TYPE=$(echo "$PROTOCOL_DATA_ALL" | cut -d'|' -f3)
        PROTOCOL_CREATED=$(echo "$PROTOCOL_DATA_ALL" | cut -d'|' -f4)
    fi
fi

# Partial match fallback
PARTIAL_MATCH=""
if [ "$PROTOCOL_FOUND" = "false" ]; then
    PARTIAL_MATCH=$(scinote_db_query "SELECT id, name, protocol_type FROM protocols WHERE LOWER(name) LIKE '%western%' OR LOWER(name) LIKE '%blot%' ORDER BY created_at DESC LIMIT 1;")
fi

# Newest protocol fallback
NEW_PROTOCOL=""
if [ "$PROTOCOL_FOUND" = "false" ]; then
    NEW_PROTOCOL=$(scinote_db_query "SELECT id, name, protocol_type FROM protocols ORDER BY created_at DESC LIMIT 1;")
fi

PROTOCOL_NAME_ESCAPED=$(json_escape "$PROTOCOL_NAME")
PARTIAL_ESCAPED=$(json_escape "$PARTIAL_MATCH")
NEW_PROTOCOL_ESCAPED=$(json_escape "$NEW_PROTOCOL")

RESULT_JSON=$(cat << EOF
{
    "initial_protocol_count": ${INITIAL_COUNT:-0},
    "current_protocol_count": ${CURRENT_COUNT:-0},
    "protocol_found": ${PROTOCOL_FOUND},
    "protocol": {
        "id": "${PROTOCOL_ID}",
        "name": "${PROTOCOL_NAME_ESCAPED}",
        "protocol_type": "${PROTOCOL_TYPE}",
        "created_at": "${PROTOCOL_CREATED}"
    },
    "partial_match": "${PARTIAL_ESCAPED}",
    "newest_protocol": "${NEW_PROTOCOL_ESCAPED}",
    "export_timestamp": "$(date -Iseconds)"
}
EOF
)

safe_write_json "/tmp/create_protocol_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/create_protocol_result.json"
cat /tmp/create_protocol_result.json
echo "=== Export complete ==="
