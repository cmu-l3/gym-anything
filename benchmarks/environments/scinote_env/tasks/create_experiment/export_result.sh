#!/bin/bash
echo "=== Exporting create_experiment result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

INITIAL_COUNT=$(cat /tmp/initial_experiment_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(get_experiment_count)

# Search for the expected experiment
EXPECTED_NAME="HPLC Analysis Run 3"
EXPERIMENT_DATA=$(scinote_db_query "SELECT e.id, e.name, p.name, e.created_at FROM experiments e JOIN projects p ON e.project_id = p.id WHERE LOWER(TRIM(e.name)) = LOWER(TRIM('${EXPECTED_NAME}')) ORDER BY e.created_at DESC LIMIT 1;")

EXPERIMENT_FOUND="false"
EXPERIMENT_ID=""
EXPERIMENT_NAME=""
PROJECT_NAME=""
EXPERIMENT_CREATED=""

if [ -n "$EXPERIMENT_DATA" ]; then
    EXPERIMENT_FOUND="true"
    EXPERIMENT_ID=$(echo "$EXPERIMENT_DATA" | cut -d'|' -f1)
    EXPERIMENT_NAME=$(echo "$EXPERIMENT_DATA" | cut -d'|' -f2)
    PROJECT_NAME=$(echo "$EXPERIMENT_DATA" | cut -d'|' -f3)
    EXPERIMENT_CREATED=$(echo "$EXPERIMENT_DATA" | cut -d'|' -f4)
fi

# Partial match fallback
PARTIAL_MATCH=""
if [ "$EXPERIMENT_FOUND" = "false" ]; then
    PARTIAL_MATCH=$(scinote_db_query "SELECT e.id, e.name, p.name FROM experiments e JOIN projects p ON e.project_id = p.id WHERE LOWER(e.name) LIKE '%hplc%' OR LOWER(e.name) LIKE '%analysis%' ORDER BY e.created_at DESC LIMIT 1;")
fi

# Newest experiment fallback
NEW_EXPERIMENT=""
if [ "$EXPERIMENT_FOUND" = "false" ]; then
    NEW_EXPERIMENT=$(scinote_db_query "SELECT e.id, e.name, p.name FROM experiments e JOIN projects p ON e.project_id = p.id ORDER BY e.created_at DESC LIMIT 1;")
fi

EXPERIMENT_NAME_ESCAPED=$(json_escape "$EXPERIMENT_NAME")
PROJECT_NAME_ESCAPED=$(json_escape "$PROJECT_NAME")
PARTIAL_ESCAPED=$(json_escape "$PARTIAL_MATCH")
NEW_EXPERIMENT_ESCAPED=$(json_escape "$NEW_EXPERIMENT")

RESULT_JSON=$(cat << EOF
{
    "initial_experiment_count": ${INITIAL_COUNT:-0},
    "current_experiment_count": ${CURRENT_COUNT:-0},
    "experiment_found": ${EXPERIMENT_FOUND},
    "experiment": {
        "id": "${EXPERIMENT_ID}",
        "name": "${EXPERIMENT_NAME_ESCAPED}",
        "project_name": "${PROJECT_NAME_ESCAPED}",
        "created_at": "${EXPERIMENT_CREATED}"
    },
    "partial_match": "${PARTIAL_ESCAPED}",
    "newest_experiment": "${NEW_EXPERIMENT_ESCAPED}",
    "export_timestamp": "$(date -Iseconds)"
}
EOF
)

safe_write_json "/tmp/create_experiment_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/create_experiment_result.json"
cat /tmp/create_experiment_result.json
echo "=== Export complete ==="
