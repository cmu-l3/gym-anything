#!/bin/bash
echo "=== Exporting configure_pause_codes result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Capture final state screenshot
take_screenshot /tmp/task_final.png

# 2. Collect Verification Data
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_pause_code_count.txt 2>/dev/null || echo "0")

# 3. Query Pause Codes from Database
# We export them as a JSON array of objects
echo "Querying pause codes..."
PAUSE_CODES_JSON=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e \
  "SELECT JSON_OBJECT('code', pause_code, 'name', pause_code_name, 'billable', billable) FROM vicidial_pause_codes WHERE campaign_id='SALESQ1';" 2>/dev/null | jq -s '.' || echo "[]")

# 4. Check Admin Logs (Anti-Gaming)
# Look for events related to PAUSECODES or modifications by user 6666 since task start
LOG_COUNT=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e \
  "SELECT COUNT(*) FROM vicidial_admin_log WHERE user='6666' AND event_date >= FROM_UNIXTIME($TASK_START) AND (event_section='PAUSECODES' OR event_sql LIKE '%vicidial_pause_codes%');" 2>/dev/null || echo "0")

# 5. Check if Browser is still running
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# 6. Construct Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "initial_code_count": $INITIAL_COUNT,
    "final_pause_codes": $PAUSE_CODES_JSON,
    "admin_log_entries": $LOG_COUNT,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 7. Move to standard location with safe permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="