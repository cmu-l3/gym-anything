#!/bin/bash
# Export script for "create_reply_template" task
# Queries the SDP database for the created template

echo "=== Exporting Reply Template Result ==="
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULT_FILE="/tmp/task_result.json"
TABLE_NAME="replytemplate"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query the database for the template
# We select columns common in SDP versions for reply templates
# Note: Column names are case-insensitive in SQL, but SDP usually uses lowercase in Postgres
echo "Querying database for template..."

# We use a Python script to handle the DB query and JSON formatting robustly
# because handling multiline descriptions/bodies in bash/SQL one-liners is error-prone.
python3 -c "
import json
import subprocess
import sys
import time

def run_query(sql):
    # Helper to run sdp_db_exec via bash
    # We use -t -A in psql usually, but let's try to get raw output
    cmd = ['bash', '-c', f'source /workspace/scripts/task_utils.sh; sdp_db_exec \"{sql}\"']
    try:
        res = subprocess.check_output(cmd, stderr=subprocess.STDOUT).decode('utf-8').strip()
        return res
    except subprocess.CalledProcessError as e:
        return ''

# 1. Check if template exists and get details
# Columns: templatename, subject, description (body)
sql = \"SELECT templatename, subject, description FROM replytemplate WHERE LOWER(templatename) = 'password reset completion'\"
raw_data = run_query(sql)

result = {
    'found': False,
    'name': '',
    'subject': '',
    'body': '',
    'task_timestamp': $TASK_START,
    'query_raw': raw_data
}

if raw_data and '|' in raw_data:
    # Postgres default output with -A is pipe separated
    parts = raw_data.split('|')
    if len(parts) >= 3:
        result['found'] = True
        result['name'] = parts[0].strip()
        result['subject'] = parts[1].strip()
        # Description might contain HTML entities or tags
        result['body'] = parts[2].strip()

print(json.dumps(result, indent=2))
" > "$RESULT_FILE"

# Make sure result file has permissions
chmod 666 "$RESULT_FILE" 2>/dev/null || true

echo "Export complete. Result:"
cat "$RESULT_FILE"
echo "=== Export Done ==="