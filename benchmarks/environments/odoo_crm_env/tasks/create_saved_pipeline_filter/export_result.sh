#!/bin/bash
set -e
echo "=== Exporting create_saved_pipeline_filter results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Get task timings
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Query the Odoo database for the filter
# We use python to query via XMLRPC or direct SQL via docker exec. 
# Docker exec SQL is more robust against broken python envs.
echo "Querying ir_filters table..."

# We fetch the most recently created filter matching the criteria
FILTER_DATA=$(docker exec odoo-db psql -U odoo -d odoodb -t -A -c "
    SELECT id, name, model_id, domain, user_id, EXTRACT(EPOCH FROM create_date)::bigint 
    FROM ir_filters 
    WHERE model_id = 'crm.lead' AND name ILIKE '%High Value%' 
    ORDER BY create_date DESC LIMIT 1;
" 2>/dev/null || echo "")

# Parse the SQL output (pipe-separated by default in psql -A)
# Format: id|name|model_id|domain|user_id|create_date_epoch
FILTER_EXISTS="false"
FILTER_NAME=""
FILTER_DOMAIN=""
FILTER_USER_ID=""
FILTER_CREATE_TIME="0"

if [ -n "$FILTER_DATA" ]; then
    FILTER_EXISTS="true"
    FILTER_NAME=$(echo "$FILTER_DATA" | cut -d'|' -f2)
    FILTER_DOMAIN=$(echo "$FILTER_DATA" | cut -d'|' -f4)
    FILTER_USER_ID=$(echo "$FILTER_DATA" | cut -d'|' -f5)
    FILTER_CREATE_TIME=$(echo "$FILTER_DATA" | cut -d'|' -f6)
fi

# 4. Check if Firefox is still running
APP_RUNNING=$(pgrep -f firefox > /dev/null && echo "true" || echo "false")

# 5. Create JSON result
# Using python to safely dump JSON (handles escaping of the domain string)
python3 -c "
import json
import sys

data = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'filter_exists': $FILTER_EXISTS,
    'filter_name': '$FILTER_NAME',
    'filter_domain': '''$FILTER_DOMAIN''',
    'filter_user_id': '$FILTER_USER_ID',
    'filter_create_time': $FILTER_CREATE_TIME,
    'app_running': $APP_RUNNING,
    'screenshot_path': '/tmp/task_final.png'
}
print(json.dumps(data, indent=2))
" > /tmp/task_result.json

# 6. Adjust permissions so host can copy it
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json