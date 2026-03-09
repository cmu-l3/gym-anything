#!/bin/bash
# Export script for create_chart_account task
# Captures database state and final screenshot

echo "=== Exporting create_chart_account result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Get Task Timings
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Query the Database for the target account
# We fetch number, name, and creation timestamp
# Using pipe delimiter for safe parsing
ACCOUNT_DATA=$(docker exec ekylibre-db psql -U ekylibre -d ekylibre_production -t -A -F"|" -c "SELECT number, name, created_at FROM accounts WHERE number = '6227';")

# Parse result
ACCOUNT_FOUND="false"
ACC_NUMBER=""
ACC_NAME=""
ACC_CREATED_AT=""

if [ -n "$ACCOUNT_DATA" ]; then
    ACCOUNT_FOUND="true"
    ACC_NUMBER=$(echo "$ACCOUNT_DATA" | cut -d'|' -f1)
    ACC_NAME=$(echo "$ACCOUNT_DATA" | cut -d'|' -f2)
    ACC_CREATED_AT=$(echo "$ACCOUNT_DATA" | cut -d'|' -f3)
fi

# 4. Get Account Counts (Initial vs Final)
FINAL_COUNT=$(ekylibre_db_query "SELECT COUNT(*) FROM accounts")
INITIAL_COUNT=$(cat /tmp/initial_account_count.txt 2>/dev/null || echo "0")

# 5. Check if Firefox is still running
APP_RUNNING="false"
if pgrep -f "firefox" > /dev/null; then
    APP_RUNNING="true"
fi

# 6. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "account_found": $ACCOUNT_FOUND,
    "account_details": {
        "number": "$ACC_NUMBER",
        "name": "$ACC_NAME",
        "created_at": "$ACC_CREATED_AT"
    },
    "initial_count": ${INITIAL_COUNT:-0},
    "final_count": ${FINAL_COUNT:-0},
    "app_running": $APP_RUNNING
}
EOF

# 7. Move JSON to standard location with permissive permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="