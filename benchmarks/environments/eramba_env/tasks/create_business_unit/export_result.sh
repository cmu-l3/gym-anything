#!/bin/bash
echo "=== Exporting create_business_unit task results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Collect Timing Data
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
INITIAL_COUNT=$(cat /tmp/initial_count.txt 2>/dev/null || echo "0")

# 3. Query Database for Result
# We look for the specific record created
DB_RESULT_JSON=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
    "SELECT JSON_OBJECT(
        'found', COUNT(*),
        'name', MAX(name),
        'description', MAX(description),
        'created', MAX(created),
        'id', MAX(id)
     )
     FROM business_units 
     WHERE name LIKE 'IT Security Operations' AND deleted=0;" 2>/dev/null)

# Handle empty result if DB query fails entirely
if [ -z "$DB_RESULT_JSON" ]; then
    DB_RESULT_JSON='{"found": 0, "name": null, "description": null, "created": null, "id": null}'
fi

# 4. Get Final Record Count
FINAL_COUNT=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e "SELECT COUNT(*) FROM business_units WHERE deleted=0;" 2>/dev/null || echo "0")

# 5. Check if App is Running
APP_RUNNING=$(pgrep -f firefox > /dev/null && echo "true" || echo "false")

# 6. Create Export JSON
# We construct a JSON object containing all evidence
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_count": $INITIAL_COUNT,
    "final_count": $FINAL_COUNT,
    "db_record": $DB_RESULT_JSON,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 7. Move to standard location with permissive permissions
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result export complete. Content:"
cat /tmp/task_result.json