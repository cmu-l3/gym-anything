#!/bin/bash
echo "=== Exporting task results ==="

# 1. Capture Final State Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 2. Query Database for Final Value
# We use the mysql CLI to get the exact value from the database
FINAL_SCALE=$(mysql -u opensis_user -p'opensis_password_123' opensis -N -e \
    "SELECT reporting_gp_scale FROM schools WHERE title = 'Demo School';" 2>/dev/null || echo "ERROR")

# Get the initial value recorded during setup
INITIAL_SCALE=$(cat /tmp/initial_gpa_scale.txt 2>/dev/null || echo "UNKNOWN")

# 3. Check System State
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
DB_RUNNING=$(systemctl is-active mariadb >/dev/null && echo "true" || echo "false")

# 4. Create JSON Result
# Use a temp file to avoid permission issues, then move to /tmp/task_result.json
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "db_service_running": $DB_RUNNING,
    "initial_gpa_scale": "$INITIAL_SCALE",
    "final_gpa_scale": "$FINAL_SCALE",
    "target_gpa_scale": "5.00",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permissive permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="