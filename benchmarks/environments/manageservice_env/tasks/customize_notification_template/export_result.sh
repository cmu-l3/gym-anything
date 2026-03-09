#!/bin/bash
# Export script for customize_notification_template

echo "=== Exporting Notification Template Results ==="
source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Query the Database for Notification Templates
# We select records that might match our criteria to verify they exist and are correct.
# We look into 'notificationtemplate' and 'notificationrule' tables.
# Note: Table names in SDP are usually lowercase in Postgres, but we handle potential casing.

echo "Querying Notification Templates..."

# Helper to dump query result to a variable
# We fetch relevant columns for rules that might be the target
# We specifically look for the modification strings
DB_RESULT=$(sdp_db_exec "
SELECT 
    nt.title, 
    nt.subject, 
    nt.message, 
    nr.status 
FROM notificationtemplate nt 
LEFT JOIN notificationrule nr ON nt.templateid = nr.templateid 
WHERE 
    nt.subject LIKE '%Global Corp%' 
    OR nt.message LIKE '%555-0199%' 
    OR nt.title LIKE '%Acknowledge requester%'
    OR nt.title LIKE '%Request Received%';
")

# If the standard join fails (schema variations), try querying just the template
if [ -z "$DB_RESULT" ]; then
    echo "Complex join returned empty, trying simple template query..."
    DB_RESULT=$(sdp_db_exec "SELECT title, subject, message, 'UNKNOWN_STATUS' FROM notificationtemplate WHERE subject LIKE '%Global Corp%' OR message LIKE '%555-0199%';")
fi

# 3. Create JSON Result
# We will save the raw DB output line-by-line into a JSON array structure
# Postgres output from sdp_db_exec is usually pipe-separated or similar depending on formatting
# Here we just save the raw string for Python to parse using simple matching

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

# Safe JSON encoding of the DB result using Python
python3 -c "
import json
import sys

raw_db = '''$DB_RESULT'''
task_start = $(cat /tmp/task_start_time.txt 2>/dev/null || echo 0)

output = {
    'db_records': raw_db,
    'task_start': task_start,
    'screenshot_path': '/tmp/task_final.png',
    'app_running': True
}

with open('$TEMP_JSON', 'w') as f:
    json.dump(output, f)
"

# 4. Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json