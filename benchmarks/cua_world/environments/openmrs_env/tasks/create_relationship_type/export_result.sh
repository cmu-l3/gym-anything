#!/bin/bash
# Export script for create_relationship_type task
# Queries the database for the newly created Relationship Type and exports status.

set -e
echo "=== Exporting create_relationship_type result ==="
source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Get Task Context
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task Start Timestamp: $TASK_START"

# 3. Query Database for the Result
# We select key fields to verify the agent entered data correctly.
# We explicitly check for the specific names requested in the task.
echo "Querying database for Relationship Type..."

# Use a complex query to get details as a single line or empty
DB_RESULT=$(omrs_db_query "SELECT a_is_to_b, b_is_to_a, description, retired, date_created FROM relationship_type WHERE a_is_to_b = 'Research Coordinator' OR b_is_to_a = 'Research Participant' ORDER BY date_created DESC LIMIT 1;" 2>/dev/null | tail -n +2 || true)

FOUND="false"
A_TO_B=""
B_TO_A=""
DESC=""
RETIRED=""
DATE_CREATED=""
CREATED_DURING_TASK="false"

if [ -n "$DB_RESULT" ]; then
    FOUND="true"
    # Parse tab-separated output from mysql -N (or standard output)
    # Result format: Research Coordinator [tab] Research Participant [tab] Description [tab] 0 [tab] 2023-10-27 10:00:00
    
    A_TO_B=$(echo "$DB_RESULT" | awk -F'\t' '{print $1}')
    B_TO_A=$(echo "$DB_RESULT" | awk -F'\t' '{print $2}')
    DESC=$(echo "$DB_RESULT" | awk -F'\t' '{print $3}')
    RETIRED=$(echo "$DB_RESULT" | awk -F'\t' '{print $4}')
    DATE_CREATED_STR=$(echo "$DB_RESULT" | awk -F'\t' '{print $5}')
    
    # Convert DB timestamp to unix for comparison
    # Handle potential differences in date format (usually YYYY-MM-DD HH:MM:SS)
    DATE_CREATED_TS=$(date -d "$DATE_CREATED_STR" +%s 2>/dev/null || echo "0")
    
    if [ "$DATE_CREATED_TS" -ge "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi
fi

# 4. JSON Export
# We use Python to write the JSON to avoid escaping issues with bash
python3 -c "
import json
import sys

data = {
    'found': $FOUND,
    'a_is_to_b': '''$A_TO_B''',
    'b_is_to_a': '''$B_TO_A''',
    'description': '''$DESC''',
    'retired': '''$RETIRED''',
    'created_during_task': $CREATED_DURING_TASK,
    'task_start': $TASK_START,
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(data, f, indent=2)
"

echo "Result exported to /tmp/task_result.json:"
cat /tmp/task_result.json
echo "=== Export complete ==="