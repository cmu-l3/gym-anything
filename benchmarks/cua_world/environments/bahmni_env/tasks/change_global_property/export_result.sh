#!/bin/bash
echo "=== Exporting change_global_property results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Gather Task Execution Data
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END_TIME=$(date +%s)
INITIAL_PROPERTY_TS=$(cat /tmp/initial_property_ts.txt 2>/dev/null || echo "0")

# 3. Check Final Value via API
API_VALUE=$(curl -sk -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
  "${OPENMRS_API_URL}/systemsetting/default_locale?v=full" 2>/dev/null \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('value','error'))" 2>/dev/null || echo "error")

# 4. Check Final Value and Timestamp via Database
# We check the DB directly to ensure the API isn't caching old values and to get the modification time
DB_JSON=$(docker exec bahmni-openmrsdb mysql -u openmrs-user -ppassword openmrs -N -e \
  "SELECT JSON_OBJECT('value', property_value, 'ts', UNIX_TIMESTAMP(COALESCE(date_changed, date_created))) FROM global_property WHERE property = 'default_locale'" 2>/dev/null)

DB_VALUE=$(echo "$DB_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('value',''))" 2>/dev/null || echo "")
DB_TS=$(echo "$DB_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('ts', 0))" 2>/dev/null || echo "0")

# 5. Check if Browser is still running
BROWSER_RUNNING=$(pgrep -f "epiphany" > /dev/null && echo "true" || echo "false")

# 6. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START_TIME,
    "task_end_time": $TASK_END_TIME,
    "initial_property_ts": $INITIAL_PROPERTY_TS,
    "final_api_value": "$API_VALUE",
    "final_db_value": "$DB_VALUE",
    "final_db_ts": $DB_TS,
    "browser_running": $BROWSER_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="