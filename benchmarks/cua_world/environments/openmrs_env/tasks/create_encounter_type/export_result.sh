#!/bin/bash
# Export script for create_encounter_type task

echo "=== Exporting Task Results ==="
source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Get Task Start Time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Query the Database for the created Encounter Type
# We look for the exact name 'Telehealth Intake' that is NOT retired.
echo "Querying database for Encounter Type..."
DB_RESULT=$(omrs_db_query "SELECT name, description, retired, date_created, creator FROM encounter_type WHERE name = 'Telehealth Intake' AND retired = 0 ORDER BY encounter_type_id DESC LIMIT 1;" 2>/dev/null)

# Parse DB Result
# Output format from mariadb -N is tab-separated: name \t description \t retired \t date_created \t creator
if [ -n "$DB_RESULT" ]; then
    FOUND="true"
    ACTUAL_NAME=$(echo "$DB_RESULT" | cut -f1)
    ACTUAL_DESC=$(echo "$DB_RESULT" | cut -f2)
    IS_RETIRED=$(echo "$DB_RESULT" | cut -f3)
    DATE_CREATED=$(echo "$DB_RESULT" | cut -f4)
    # Convert SQL datetime to timestamp for comparison
    CREATED_TS=$(date -d "$DATE_CREATED" +%s 2>/dev/null || echo "0")
else
    FOUND="false"
    ACTUAL_NAME=""
    ACTUAL_DESC=""
    IS_RETIRED=""
    CREATED_TS="0"
fi

# 4. Create JSON Result
# Using python to safely handle JSON escaping for the description string
python3 -c "
import json
import os

try:
    result = {
        'found': $FOUND,
        'actual_name': '''$ACTUAL_NAME''',
        'actual_description': '''$ACTUAL_DESC''',
        'is_retired': '$IS_RETIRED' == '1',
        'created_timestamp': $CREATED_TS,
        'task_start_timestamp': $TASK_START,
        'screenshot_path': '/tmp/task_final.png'
    }
    
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f, indent=2)
except Exception as e:
    print(f'Error generating JSON: {e}')
"

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="