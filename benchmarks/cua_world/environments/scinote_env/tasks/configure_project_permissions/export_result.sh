#!/bin/bash
echo "=== Exporting configure_project_permissions result ==="

source /workspace/scripts/task_utils.sh

# Record final state visually
take_screenshot /tmp/task_final.png

# Retrieve task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Fetch IDs
PROJ_ID=$(scinote_db_query "SELECT id FROM projects WHERE name='Zebrafish Gene Editing' LIMIT 1;" | tr -d '[:space:]')
JANE_ID=$(scinote_db_query "SELECT id FROM users WHERE email='jane.doe@example.com' LIMIT 1;" | tr -d '[:space:]')
JOHN_ID=$(scinote_db_query "SELECT id FROM users WHERE email='john.smith@example.com' LIMIT 1;" | tr -d '[:space:]')
SARAH_ID=$(scinote_db_query "SELECT id FROM users WHERE email='sarah.connor@example.com' LIMIT 1;" | tr -d '[:space:]')

# Guard check: Ensure project and users exist
if [ -z "$PROJ_ID" ] || [ -z "$JANE_ID" ]; then
    echo "ERROR: Critical database records missing. Exporting fallback JSON."
    RESULT_JSON='{"error": "Project or Users missing from database", "task_start": '"$TASK_START"'}'
    safe_write_json "/tmp/permissions_task_result.json" "$RESULT_JSON"
    exit 0
fi

# Retrieve roles
JANE_ROLE=$(scinote_db_query "SELECT ur.name FROM user_assignments ua JOIN user_roles ur ON ua.user_role_id = ur.id WHERE ua.assignable_type='Project' AND ua.assignable_id=${PROJ_ID} AND ua.user_id=${JANE_ID};" | tr -d '[:space:]')
JOHN_ROLE=$(scinote_db_query "SELECT ur.name FROM user_assignments ua JOIN user_roles ur ON ua.user_role_id = ur.id WHERE ua.assignable_type='Project' AND ua.assignable_id=${PROJ_ID} AND ua.user_id=${JOHN_ID};" | tr -d '[:space:]')
SARAH_ROLE=$(scinote_db_query "SELECT ur.name FROM user_assignments ua JOIN user_roles ur ON ua.user_role_id = ur.id WHERE ua.assignable_type='Project' AND ua.assignable_id=${PROJ_ID} AND ua.user_id=${SARAH_ID};" | tr -d '[:space:]')

# Retrieve modification timestamps (Epoch seconds) to detect if changes happened during the task
JOHN_UPDATED=$(scinote_db_query "SELECT EXTRACT(EPOCH FROM updated_at) FROM user_assignments WHERE assignable_type='Project' AND assignable_id=${PROJ_ID} AND user_id=${JOHN_ID};" | tr -d '[:space:]' | cut -d. -f1)
SARAH_UPDATED=$(scinote_db_query "SELECT EXTRACT(EPOCH FROM updated_at) FROM user_assignments WHERE assignable_type='Project' AND assignable_id=${PROJ_ID} AND user_id=${SARAH_ID};" | tr -d '[:space:]' | cut -d. -f1)

# Format the results into a JSON file
RESULT_JSON=$(cat << EOF
{
    "task_start": ${TASK_START:-0},
    "project_id": "${PROJ_ID}",
    "jane_role": "${JANE_ROLE}",
    "john_role": "${JOHN_ROLE}",
    "sarah_role": "${SARAH_ROLE}",
    "john_assignment_updated_at": ${JOHN_UPDATED:-0},
    "sarah_assignment_updated_at": ${SARAH_UPDATED:-0},
    "export_timestamp": "$(date -Iseconds)",
    "screenshot_path": "/tmp/task_final.png"
}
EOF
)

safe_write_json "/tmp/permissions_task_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/permissions_task_result.json"
cat /tmp/permissions_task_result.json
echo "=== Export complete ==="