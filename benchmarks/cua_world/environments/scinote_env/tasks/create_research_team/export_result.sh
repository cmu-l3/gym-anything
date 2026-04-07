#!/bin/bash
echo "=== Exporting create_research_team result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Read setup variables
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_TEAM_COUNT=$(cat /tmp/initial_team_count 2>/dev/null || echo "0")
INITIAL_PROJECT_COUNT=$(cat /tmp/initial_project_count 2>/dev/null || echo "0")
DEFAULT_TEAM_ID=$(cat /tmp/default_team_id 2>/dev/null || echo "1")

# Get current counts
CURRENT_TEAM_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM teams;" | tr -d '[:space:]')
CURRENT_PROJECT_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM projects;" | tr -d '[:space:]')

EXPECTED_TEAM="CRISPR Gene Therapy Consortium"
EXPECTED_PROJECT="AAV Vector Optimization Study"

# Query the database for the new team
TEAM_DATA=$(scinote_db_query "SELECT id, name, EXTRACT(EPOCH FROM created_at) FROM teams WHERE name='${EXPECTED_TEAM}' ORDER BY created_at DESC LIMIT 1;")

TEAM_FOUND="false"
TEAM_ID=""
TEAM_NAME=""
TEAM_CREATED_EPOCH="0"

if [ -n "$TEAM_DATA" ]; then
    TEAM_FOUND="true"
    TEAM_ID=$(echo "$TEAM_DATA" | cut -d'|' -f1 | tr -d '[:space:]')
    TEAM_NAME=$(echo "$TEAM_DATA" | cut -d'|' -f2)
    TEAM_CREATED_EPOCH=$(echo "$TEAM_DATA" | cut -d'|' -f3 | cut -d'.' -f1)
fi

# Query the database for the new project
PROJECT_DATA=$(scinote_db_query "SELECT id, name, team_id, EXTRACT(EPOCH FROM created_at) FROM projects WHERE name='${EXPECTED_PROJECT}' ORDER BY created_at DESC LIMIT 1;")

PROJECT_FOUND="false"
PROJECT_ID=""
PROJECT_NAME=""
PROJECT_TEAM_ID=""
PROJECT_CREATED_EPOCH="0"

if [ -n "$PROJECT_DATA" ]; then
    PROJECT_FOUND="true"
    PROJECT_ID=$(echo "$PROJECT_DATA" | cut -d'|' -f1 | tr -d '[:space:]')
    PROJECT_NAME=$(echo "$PROJECT_DATA" | cut -d'|' -f2)
    PROJECT_TEAM_ID=$(echo "$PROJECT_DATA" | cut -d'|' -f3 | tr -d '[:space:]')
    PROJECT_CREATED_EPOCH=$(echo "$PROJECT_DATA" | cut -d'|' -f4 | cut -d'.' -f1)
fi

# Escape text for JSON safety
TEAM_NAME_ESCAPED=$(json_escape "$TEAM_NAME")
PROJECT_NAME_ESCAPED=$(json_escape "$PROJECT_NAME")

# Write verification data to JSON
RESULT_JSON=$(cat << EOF
{
    "task_start_time": ${TASK_START},
    "initial_team_count": ${INITIAL_TEAM_COUNT},
    "current_team_count": ${CURRENT_TEAM_COUNT:-0},
    "initial_project_count": ${INITIAL_PROJECT_COUNT},
    "current_project_count": ${CURRENT_PROJECT_COUNT:-0},
    "default_team_id": "${DEFAULT_TEAM_ID}",
    "team_found": ${TEAM_FOUND},
    "team": {
        "id": "${TEAM_ID}",
        "name": "${TEAM_NAME_ESCAPED}",
        "created_epoch": ${TEAM_CREATED_EPOCH:-0}
    },
    "project_found": ${PROJECT_FOUND},
    "project": {
        "id": "${PROJECT_ID}",
        "name": "${PROJECT_NAME_ESCAPED}",
        "team_id": "${PROJECT_TEAM_ID}",
        "created_epoch": ${PROJECT_CREATED_EPOCH:-0}
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF
)

safe_write_json "/tmp/create_team_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/create_team_result.json"
cat /tmp/create_team_result.json
echo "=== Export complete ==="