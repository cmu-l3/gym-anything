#!/bin/bash
echo "=== Exporting clone_adapt_campaign_settings result ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query the database for the target campaign 'SEN_WEST'
# We fetch relevant fields to a JSON object
echo "Querying database for SEN_WEST..."

# We use python to run the SQL query inside docker and format as JSON to avoid bash parsing hell
docker exec vicidial python3 -c "
import MySQLdb
import json
import sys

try:
    db = MySQLdb.connect(host='localhost', user='cron', passwd='1234', db='asterisk')
    cursor = db.cursor()
    
    # Check if campaign exists
    cursor.execute(\"SELECT count(*) FROM vicidial_campaigns WHERE campaign_id='SEN_WEST'\")
    exists = cursor.fetchone()[0] > 0
    
    data = {}
    if exists:
        # Fetch details
        query = \"\"\"
            SELECT 
                campaign_id, campaign_name, active, 
                campaign_cid, manual_dial_prefix,
                dial_method, auto_dial_level, dial_timeout, drop_call_seconds, voicemail_ext,
                campaign_logindate
            FROM vicidial_campaigns 
            WHERE campaign_id='SEN_WEST'
        \"\"\"
        cursor.execute(query)
        row = cursor.fetchone()
        
        # Map fields
        data = {
            'campaign_id': row[0],
            'campaign_name': row[1],
            'active': row[2],
            'campaign_cid': row[3],
            'manual_dial_prefix': row[4],
            'dial_method': row[5],
            'auto_dial_level': str(row[6]), # float/decimal to string
            'dial_timeout': row[7],
            'drop_call_seconds': row[8],
            'voicemail_ext': row[9],
            'entry_date': str(row[10]) if row[10] else None
        }

    print(json.dumps({'exists': exists, 'data': data}))

except Exception as e:
    print(json.dumps({'error': str(e), 'exists': False}))
" > /tmp/db_result.json

# Check if application (Firefox) is running
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# Combine into final result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "db_result": $(cat /tmp/db_result.json),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="