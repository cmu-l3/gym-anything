#!/bin/bash
echo "=== Exporting Add Warrant Type Result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final State Visuals
take_screenshot /tmp/task_final.png

# 2. Retrieve Initial State Data
INITIAL_COUNT=$(cat /tmp/initial_warrant_type_count 2>/dev/null || echo "0")
INITIAL_MAX_ID=$(cat /tmp/initial_max_id 2>/dev/null || echo "0")

# 3. Query Current State
# Check current count
CURRENT_COUNT=$(opencad_db_query "SELECT COUNT(*) FROM warrant_types")

# Search for the specific record 'Failure to Appear'
# We check for case-insensitive match
TARGET_RECORD=$(opencad_db_query "SELECT id, warrant_type FROM warrant_types WHERE LOWER(TRIM(warrant_type)) = 'failure to appear' ORDER BY id DESC LIMIT 1")

RECORD_FOUND="false"
RECORD_ID=""
RECORD_NAME=""
IS_NEW_RECORD="false"

if [ -n "$TARGET_RECORD" ]; then
    RECORD_FOUND="true"
    RECORD_ID=$(echo "$TARGET_RECORD" | cut -f1)
    RECORD_NAME=$(echo "$TARGET_RECORD" | cut -f2)

    # Verify it is a NEW record (ID > Initial Max ID)
    if [ "$RECORD_ID" -gt "$INITIAL_MAX_ID" ]; then
        IS_NEW_RECORD="true"
    fi
fi

# 4. Check Authentication State (Bonus check)
# Check if user with ID 2 (Admin) has a recent session or log
# (Optional, but good for context)

# 5. Construct JSON Result
# use jq if available, otherwise cat heredoc
RESULT_JSON=$(cat << EOF
{
    "initial_count": ${INITIAL_COUNT:-0},
    "current_count": ${CURRENT_COUNT:-0},
    "record_found": ${RECORD_FOUND},
    "record": {
        "id": "${RECORD_ID}",
        "name": "$(json_escape "${RECORD_NAME}")",
        "is_new": ${IS_NEW_RECORD}
    },
    "timestamp": "$(date -Iseconds)"
}
EOF
)

# 6. Save Result Securely
safe_write_result "$RESULT_JSON" /tmp/add_warrant_type_result.json

echo "Result saved to /tmp/add_warrant_type_result.json"
cat /tmp/add_warrant_type_result.json
echo "=== Export Complete ==="