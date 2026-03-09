#!/bin/bash
set -e
echo "=== Exporting create_account_review results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Extract Data from Database
# We are looking for the record created by the agent.
# We fetch details to verify content and timestamps.

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_count.txt 2>/dev/null || echo "0")

echo "Searching for created record..."

# Query for the specific title
# We use JSON_OBJECT to format the output directly from MySQL if possible, 
# otherwise we output raw text and parse it.
# Note: created field format in Eramba is typically 'YYYY-MM-DD HH:MM:SS'
SQL_QUERY="SELECT id, name, description, created FROM account_reviews WHERE name LIKE '%Q1 2025 Core Banking Access Review%' ORDER BY id DESC LIMIT 1;"
RECORD_DATA=$(eramba_db_query "$SQL_QUERY")

RECORD_FOUND="false"
RECORD_ID=""
RECORD_NAME=""
RECORD_DESC=""
RECORD_CREATED=""
CREATED_DURING_TASK="false"

if [ -n "$RECORD_DATA" ]; then
    RECORD_FOUND="true"
    # Parse tab-separated values
    RECORD_ID=$(echo "$RECORD_DATA" | awk -F'\t' '{print $1}')
    RECORD_NAME=$(echo "$RECORD_DATA" | awk -F'\t' '{print $2}')
    RECORD_DESC=$(echo "$RECORD_DATA" | awk -F'\t' '{print $3}')
    RECORD_CREATED_STR=$(echo "$RECORD_DATA" | awk -F'\t' '{print $4}')
    
    # Convert MySQL datetime to timestamp for comparison
    if [ -n "$RECORD_CREATED_STR" ]; then
        RECORD_TS=$(date -d "$RECORD_CREATED_STR" +%s 2>/dev/null || echo "0")
        if [ "$RECORD_TS" -ge "$TASK_START" ]; then
            CREATED_DURING_TASK="true"
        fi
    fi
fi

# Get final count
FINAL_COUNT=$(eramba_db_query "SELECT COUNT(*) FROM account_reviews;" 2>/dev/null || echo "0")
COUNT_DELTA=$((FINAL_COUNT - INITIAL_COUNT))

# 3. Create JSON Result
# Using python to safely construct JSON prevents quoting issues
python3 -c "
import json
import os

data = {
    'record_found': $RECORD_FOUND,
    'record_id': '$RECORD_ID',
    'record_name': '''$RECORD_NAME''',
    'record_description': '''$RECORD_DESC''',
    'created_during_task': $CREATED_DURING_TASK,
    'initial_count': int('$INITIAL_COUNT'),
    'final_count': int('$FINAL_COUNT'),
    'count_delta': int('$COUNT_DELTA'),
    'task_start_ts': int('$TASK_START'),
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(data, f, indent=2)
"

# Set permissions so the host can read it via copy_from_env
chmod 644 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json