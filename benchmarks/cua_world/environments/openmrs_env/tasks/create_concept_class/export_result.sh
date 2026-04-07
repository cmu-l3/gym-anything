#!/bin/bash
echo "=== Exporting create_concept_class results ==="
source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Query the database for the specific record
# We select all relevant fields to verify content and timestamps
echo "Querying database for 'SDOH' concept class..."

# Use a temporary file to store raw SQL output
RAW_OUTPUT=$(mktemp)

# Query: name, description, abbreviation, retired, date_created (unix timestamp), creator
omrs_db_query "SELECT name, description, abbreviation, retired, UNIX_TIMESTAMP(date_created) FROM concept_class WHERE name = 'SDOH';" > "$RAW_OUTPUT"

# Read result
# Expected format: SDOH  Social factors...  SDOH  0  1712345678
read -r NAME DESC ABBREV RETIRED DATE_CREATED < "$RAW_OUTPUT"

# Check if record exists
RECORD_EXISTS="false"
if [ -n "$NAME" ]; then
    RECORD_EXISTS="true"
fi

# Clean up raw output
rm -f "$RAW_OUTPUT"

# 3. Get Task Start Time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 4. Determine if created during task
CREATED_DURING_TASK="false"
if [ "$RECORD_EXISTS" = "true" ] && [ -n "$DATE_CREATED" ]; then
    if [ "$DATE_CREATED" -ge "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi
fi

# 5. Create JSON result
# Use python to safely construct JSON to handle potential special chars in description
python3 -c "
import json
import os

result = {
    'record_exists': $RECORD_EXISTS,
    'name': '$NAME',
    'description': '$DESC',
    'abbreviation': '$ABBREV',
    'retired': '$RETIRED',
    'date_created': '$DATE_CREATED',
    'task_start_time': '$TASK_START',
    'created_during_task': $CREATED_DURING_TASK
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# 6. Set permissions
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="