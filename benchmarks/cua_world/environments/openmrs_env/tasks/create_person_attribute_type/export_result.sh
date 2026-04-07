#!/bin/bash
# Export: create_person_attribute_type task
# Queries the database for the created attribute type and exports details to JSON.

echo "=== Exporting create_person_attribute_type results ==="
source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Get Task Start Time
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# 3. Query the database for the specific attribute type
# We fetch relevant fields. date_created is returned as 'YYYY-MM-DD HH:MM:SS' usually.
# We use python to handle the SQL output parsing safely.

# Helper to run query and return JSON-like structure
# We select: name, format, description, retired, UNIX_TIMESTAMP(date_created)
SQL="SELECT name, format, description, retired, UNIX_TIMESTAMP(date_created) FROM person_attribute_type WHERE name = 'Driver\'s License Number';"

# Run query
# Output format from mariadb -N is tab-separated
DB_RESULT=$(omrs_db_query "$SQL")

# Parse result
EXISTS="false"
ACTUAL_NAME=""
ACTUAL_FORMAT=""
ACTUAL_DESC=""
ACTUAL_RETIRED=""
DATE_CREATED_TS="0"

if [ -n "$DB_RESULT" ]; then
    EXISTS="true"
    # Read tab-separated values
    # Note: Description might contain spaces, so we should be careful.
    # We'll use python to parse the raw line if possible, or just awk.
    
    # IFS tab parsing
    IFS=$'\t' read -r ACTUAL_NAME ACTUAL_FORMAT ACTUAL_DESC ACTUAL_RETIRED DATE_CREATED_TS <<< "$DB_RESULT"
fi

# 4. Create JSON result
# Use python to generate JSON to handle escaping correctly
python3 -c "
import json
import os
import sys

try:
    result = {
        'exists': $EXISTS,
        'task_start_ts': $TASK_START,
        'date_created_ts': int('$DATE_CREATED_TS') if '$DATE_CREATED_TS' and '$DATE_CREATED_TS' != '0' else 0,
        'actual_name': \"$ACTUAL_NAME\",
        'actual_format': \"$ACTUAL_FORMAT\",
        'actual_description': \"$ACTUAL_DESC\",
        'actual_retired': True if \"$ACTUAL_RETIRED\" == '1' else False,
        'screenshot_path': '/tmp/task_final.png'
    }
    
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f, indent=2)
        
except Exception as e:
    print(f'Error creating JSON: {e}', file=sys.stderr)
"

# 5. Permission fix
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json:"
cat /tmp/task_result.json
echo "=== Export complete ==="