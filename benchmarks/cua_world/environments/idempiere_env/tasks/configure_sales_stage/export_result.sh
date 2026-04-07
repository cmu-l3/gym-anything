#!/bin/bash
set -e
echo "=== Exporting Configure Sales Stage results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# ---------------------------------------------------------------
# 1. Capture Final Screenshot
# ---------------------------------------------------------------
echo "Capturing final state..."
take_screenshot /tmp/task_final.png

# ---------------------------------------------------------------
# 2. Query Database for Result
# ---------------------------------------------------------------
# We look for the record created by the agent.
# We fetch relevant columns: Name, Value (SearchKey), Probability, Description, IsActive
# We filter by the expected Search Key 'Verbal'
# Note: idempiere_query returns pipe-separated values by default or we can format it.
# We will construct a JSON object manually using jq or python to be safe with special chars.

echo "Querying C_SalesStage table..."

# Get raw data (pipe separated)
# Using 'TRIM' to remove whitespace padding
RAW_DATA=$(idempiere_query "SELECT TRIM(Name) || '|' || TRIM(Value) || '|' || Probability || '|' || TRIM(Description) || '|' || IsActive || '|' || Created FROM C_SalesStage WHERE Value='Verbal' ORDER BY Created DESC LIMIT 1")

# Default values if not found
NAME=""
VALUE=""
PROBABILITY="0"
DESCRIPTION=""
IS_ACTIVE="N"
CREATED_TIMESTAMP=""
RECORD_FOUND="false"

if [ -n "$RAW_DATA" ]; then
    RECORD_FOUND="true"
    # Parse the pipe-separated line
    NAME=$(echo "$RAW_DATA" | cut -d'|' -f1)
    VALUE=$(echo "$RAW_DATA" | cut -d'|' -f2)
    PROBABILITY=$(echo "$RAW_DATA" | cut -d'|' -f3)
    DESCRIPTION=$(echo "$RAW_DATA" | cut -d'|' -f4)
    IS_ACTIVE=$(echo "$RAW_DATA" | cut -d'|' -f5)
    CREATED_TIMESTAMP=$(echo "$RAW_DATA" | cut -d'|' -f6)
fi

# Get task start time for anti-gaming check
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# ---------------------------------------------------------------
# 3. Create JSON Result
# ---------------------------------------------------------------
JSON_OUTPUT="/tmp/task_result.json"

# Use Python to generate valid JSON to handle potential special characters in description
python3 -c "
import json
import sys

data = {
    'record_found': '$RECORD_FOUND' == 'true',
    'name': '''$NAME''',
    'value': '''$VALUE''',
    'probability': $PROBABILITY,
    'description': '''$DESCRIPTION''',
    'is_active': '$IS_ACTIVE' == 'Y',
    'created_timestamp': '''$CREATED_TIMESTAMP''',
    'task_start_timestamp': $TASK_START
}

with open('$JSON_OUTPUT', 'w') as f:
    json.dump(data, f, indent=2)
"

# Set permissions so the host can copy it
chmod 666 "$JSON_OUTPUT"

echo "Result exported to $JSON_OUTPUT"
cat "$JSON_OUTPUT"
echo "=== Export complete ==="