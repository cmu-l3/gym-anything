#!/bin/bash
echo "=== Exporting strategic_taskforce_time_configuration result ==="

source /workspace/scripts/task_utils.sh

# Record end state
take_screenshot /tmp/task_end_screenshot.png

log "Querying database for Time module configuration..."

# 1. Check for the Client
CLIENT_ID=$(sentrifugo_db_query "SELECT id FROM main_clients WHERE clientname='Executive Strategy Board' AND isactive=1 LIMIT 1;" | tr -d '[:space:]')

# 2. Check for the Project
PROJ_ROW=$(sentrifugo_db_query "SELECT id, client_id FROM main_projects WHERE projectname='AI Enterprise Integration' AND isactive=1 LIMIT 1;")

PROJ_ID=""
PROJ_CLIENT_ID=""
if [ -n "$PROJ_ROW" ]; then
    PROJ_ID=$(echo "$PROJ_ROW" | cut -f1 | tr -d '[:space:]')
    PROJ_CLIENT_ID=$(echo "$PROJ_ROW" | cut -f2 | tr -d '[:space:]')
fi

# 3. Check for Project Tasks
TASKS_JSON="[]"
if [ -n "$PROJ_ID" ]; then
    TASKS=$(sentrifugo_db_query "SELECT taskname FROM main_projecttasks WHERE project_id='$PROJ_ID' AND isactive=1;")
    TASKS_JSON=$(python3 -c "import sys, json; print(json.dumps([line.strip() for line in sys.stdin if line.strip()]))" <<< "$TASKS")
fi

# 4. Check for Allocated Resources
RESOURCES_JSON="[]"
if [ -n "$PROJ_ID" ]; then
    RES=$(sentrifugo_db_query "SELECT u.employeeId FROM main_projectresources pr JOIN main_users u ON pr.user_id=u.id WHERE pr.project_id='$PROJ_ID';")
    RESOURCES_JSON=$(python3 -c "import sys, json; print(json.dumps([line.strip() for line in sys.stdin if line.strip()]))" <<< "$RES")
fi

# Create Result JSON
TEMP_JSON=$(mktemp /tmp/time_config_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "client_id": "$CLIENT_ID",
    "project_id": "$PROJ_ID",
    "project_client_id": "$PROJ_CLIENT_ID",
    "tasks": $TASKS_JSON,
    "resources": $RESOURCES_JSON,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move securely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export Complete ==="