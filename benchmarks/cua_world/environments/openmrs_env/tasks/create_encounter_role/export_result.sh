#!/bin/bash
# Export: create_encounter_role task
# Queries the database for the created role and exports details to JSON.

echo "=== Exporting create_encounter_role result ==="
source /workspace/scripts/task_utils.sh

# Get task start time
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
EXPORT_TIME=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query the database for the role
# We fetch name, description, retired status, and creation date
# Note: UNIX_TIMESTAMP(date_created) helps with comparison
SQL="SELECT name, description, retired, UNIX_TIMESTAMP(date_created) FROM encounter_role WHERE name = 'Medical Scribe'"

RESULT_STR=$(omrs_db_query "$SQL")

# Parse result (MariaDB output is tab-separated)
# Expected: Medical Scribe	Assists with documentation	0	1715000000
ROLE_FOUND="false"
ROLE_NAME=""
ROLE_DESC=""
ROLE_RETIRED=""
ROLE_CREATED_TS="0"

if [ -n "$RESULT_STR" ]; then
    ROLE_FOUND="true"
    ROLE_NAME=$(echo "$RESULT_STR" | cut -f1)
    ROLE_DESC=$(echo "$RESULT_STR" | cut -f2)
    ROLE_RETIRED=$(echo "$RESULT_STR" | cut -f3)
    ROLE_CREATED_TS=$(echo "$RESULT_STR" | cut -f4)
fi

# Check if application (Firefox) is still running
APP_RUNNING="false"
if pgrep -f firefox > /dev/null; then
    APP_RUNNING="true"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "export_timestamp": $EXPORT_TIME,
    "role_found": $ROLE_FOUND,
    "role_name": "$ROLE_NAME",
    "role_description": "$ROLE_DESC",
    "role_retired": "$ROLE_RETIRED",
    "role_created_timestamp": $ROLE_CREATED_TS,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with permissive permissions
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Exported result to /tmp/task_result.json:"
cat /tmp/task_result.json
echo "=== Export Complete ==="