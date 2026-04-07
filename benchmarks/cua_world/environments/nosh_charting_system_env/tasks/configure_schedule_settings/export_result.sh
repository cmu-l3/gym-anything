#!/bin/bash
set -e
echo "=== Exporting task results ==="

# 1. Record task end time and timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TIMESTAMP=$(date -Iseconds)

# 2. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 3. Query the database for the final state
# We check the 'schedule_increment' for provider id=2 (Dr. James Carter)
FINAL_VAL=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
    "SELECT schedule_increment FROM providers WHERE id=2;" 2>/dev/null || echo "ERROR")

echo "Final DB Value: $FINAL_VAL"

# 4. Check if application containers are still running
APP_RUNNING="false"
if docker ps | grep -q "nosh-app"; then
    APP_RUNNING="true"
fi

# 5. Create JSON result file
# Use a temp file to avoid permission issues during creation
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "timestamp": "$TIMESTAMP",
    "final_schedule_increment": "$FINAL_VAL",
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 6. Move to final location with permissive permissions
# The verifier running on host needs to read this via copy_from_env
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="