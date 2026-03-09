#!/bin/bash
echo "=== Exporting create_project result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Read initial count
INITIAL_COUNT=$(cat /tmp/initial_project_count 2>/dev/null || echo "0")

# Query current project count
CURRENT_COUNT=$(get_project_count)

# Search for the expected project
EXPECTED_NAME="Protein Crystallization Study"
PROJECT_DATA=$(scinote_db_query "SELECT id, name, created_at FROM projects WHERE LOWER(TRIM(name)) = LOWER(TRIM('${EXPECTED_NAME}')) ORDER BY created_at DESC LIMIT 1;")

PROJECT_FOUND="false"
PROJECT_ID=""
PROJECT_NAME=""
PROJECT_CREATED=""

if [ -n "$PROJECT_DATA" ]; then
    PROJECT_FOUND="true"
    PROJECT_ID=$(echo "$PROJECT_DATA" | cut -d'|' -f1)
    PROJECT_NAME=$(echo "$PROJECT_DATA" | cut -d'|' -f2)
    PROJECT_CREATED=$(echo "$PROJECT_DATA" | cut -d'|' -f3)
fi

# Also check for partial matches
PARTIAL_MATCH=""
if [ "$PROJECT_FOUND" = "false" ]; then
    PARTIAL_MATCH=$(scinote_db_query "SELECT id, name FROM projects WHERE LOWER(name) LIKE '%protein%' OR LOWER(name) LIKE '%crystal%' ORDER BY created_at DESC LIMIT 1;")
fi

# Check if any new project was created
NEW_PROJECT=""
if [ "$PROJECT_FOUND" = "false" ] && [ -n "$INITIAL_COUNT" ]; then
    NEW_PROJECT=$(scinote_db_query "SELECT id, name FROM projects ORDER BY created_at DESC LIMIT 1;")
fi

# Escape strings for JSON
PROJECT_NAME_ESCAPED=$(json_escape "$PROJECT_NAME")
PARTIAL_ESCAPED=$(json_escape "$PARTIAL_MATCH")
NEW_PROJECT_ESCAPED=$(json_escape "$NEW_PROJECT")

# Build result JSON
RESULT_JSON=$(cat << EOF
{
    "initial_project_count": ${INITIAL_COUNT:-0},
    "current_project_count": ${CURRENT_COUNT:-0},
    "project_found": ${PROJECT_FOUND},
    "project": {
        "id": "${PROJECT_ID}",
        "name": "${PROJECT_NAME_ESCAPED}",
        "created_at": "${PROJECT_CREATED}"
    },
    "partial_match": "${PARTIAL_ESCAPED}",
    "newest_project": "${NEW_PROJECT_ESCAPED}",
    "export_timestamp": "$(date -Iseconds)"
}
EOF
)

safe_write_json "/tmp/create_project_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/create_project_result.json"
cat /tmp/create_project_result.json
echo "=== Export complete ==="
