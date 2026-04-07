#!/bin/bash
echo "=== Exporting configure_notifications result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Capture task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Use Python inside the container to query DB and construct structured JSON result
# This avoids fragile bash string parsing for SQL results
docker exec orangehrm python3 -c "
import json
import pymysql
import sys

# DB Connection
try:
    conn = pymysql.connect(
        host='orangehrm-db',
        user='$DB_USER',
        password='$DB_PASS',
        database='$DB_NAME',
        charset='utf8mb4',
        cursorclass=pymysql.cursors.DictCursor
    )
except Exception as e:
    print(json.dumps({'error': str(e)}))
    sys.exit(0)

result = {
    'config': {},
    'subscribers': [],
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'error': None
}

try:
    with conn.cursor() as cursor:
        # 1. Get Email Configuration
        cursor.execute('SELECT * FROM ohrm_email_configuration LIMIT 1')
        config_row = cursor.fetchone()
        if config_row:
            result['config'] = config_row
        
        # 2. Get All Subscribers with Notification Names
        # Join with notification table to get the readable name
        query = '''
            SELECT s.name as subscriber_name, s.email, n.name as notification_name, s.id as subscriber_id
            FROM ohrm_email_subscriber s
            JOIN ohrm_email_notification n ON s.notification_id = n.id
        '''
        cursor.execute(query)
        subs = cursor.fetchall()
        result['subscribers'] = subs

except Exception as e:
    result['error'] = str(e)

finally:
    conn.close()

print(json.dumps(result, indent=2, default=str))
" > /tmp/task_result.json

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Exported data:"
cat /tmp/task_result.json

echo "=== Export complete ==="