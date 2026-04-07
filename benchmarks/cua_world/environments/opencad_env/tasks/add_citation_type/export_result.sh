#!/bin/bash
echo "=== Exporting add_citation_type result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Read initial state
INITIAL_COUNT=$(cat /tmp/initial_citation_type_count 2>/dev/null || echo "0")
INITIAL_MAX_ID=$(cat /tmp/initial_max_id 2>/dev/null || echo "0")

# Get current state
CURRENT_COUNT=$(opencad_db_query "SELECT COUNT(*) FROM citation_types")

# Search for the specific citation type
# We look for exact match first, then loose match
TARGET_NAME="Equipment Safety Violation"
MATCH_EXACT="false"
MATCH_LOOSE="false"
FOUND_ID=""
FOUND_NAME=""

# Check exact match
EXACT_ID=$(opencad_db_query "SELECT id FROM citation_types WHERE citation_type = '${TARGET_NAME}' LIMIT 1")
if [ -n "$EXACT_ID" ]; then
    MATCH_EXACT="true"
    MATCH_LOOSE="true"
    FOUND_ID="$EXACT_ID"
    FOUND_NAME="$TARGET_NAME"
else
    # Check loose match (case insensitive, partial)
    LOOSE_ID=$(opencad_db_query "SELECT id FROM citation_types WHERE LOWER(citation_type) LIKE '%equipment%safety%violation%' LIMIT 1")
    if [ -n "$LOOSE_ID" ]; then
        MATCH_LOOSE="true"
        FOUND_ID="$LOOSE_ID"
        FOUND_NAME=$(opencad_db_query "SELECT citation_type FROM citation_types WHERE id = ${LOOSE_ID}")
    fi
fi

# Check if the found ID is new (created during task)
IS_NEW="false"
if [ -n "$FOUND_ID" ] && [ "$FOUND_ID" -gt "$INITIAL_MAX_ID" ]; then
    IS_NEW="true"
fi

# Create result JSON
RESULT_JSON=$(cat << EOF
{
    "initial_count": ${INITIAL_COUNT:-0},
    "current_count": ${CURRENT_COUNT:-0},
    "target_found_exact": ${MATCH_EXACT},
    "target_found_loose": ${MATCH_LOOSE},
    "found_entry": {
        "id": "$(json_escape "${FOUND_ID}")",
        "name": "$(json_escape "${FOUND_NAME}")",
        "is_new_record": ${IS_NEW}
    },
    "timestamp": "$(date -Iseconds)"
}
EOF
)

safe_write_result "$RESULT_JSON" /tmp/add_citation_type_result.json

echo "Result saved to /tmp/add_citation_type_result.json"
cat /tmp/add_citation_type_result.json
echo "=== Export complete ==="