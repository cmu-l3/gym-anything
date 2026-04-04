#!/bin/bash
echo "=== Exporting Retire Location Results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Gather Task Context
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
LOCATION_UUID=$(cat /tmp/target_location_uuid.txt 2>/dev/null)
INITIAL_RETIRED=$(cat /tmp/initial_retired_state.txt 2>/dev/null || echo "False")

if [ -z "$LOCATION_UUID" ]; then
    echo "ERROR: Location UUID not found. Setup may have failed."
    # Create empty failure result
    echo '{"error": "Setup failed"}' > /tmp/task_result.json
    exit 0
fi

# 3. Query OpenMRS REST API (Primary Verification)
# includeAll=true is REQUIRED to see retired locations
echo "Querying API for location status..."
API_RES=$(openmrs_api_get "/location/$LOCATION_UUID?v=full&includeAll=true")

# Extract fields safely using Python
read -r API_EXISTS API_RETIRED API_REASON <<EOF
$(echo "$API_RES" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    exists = 'true' if 'uuid' in d else 'false'
    retired = str(d.get('retired', False)).lower()
    reason = d.get('retireReason', '').replace('\n', ' ')
    print(f'{exists} {retired} {reason}')
except Exception:
    print('false false none')
")
EOF

# 4. Query Database Directly (Secondary/Anti-Gaming Verification)
# Check retired status and timestamp
echo "Querying Database..."
DB_QUERY="SELECT retired, retire_reason, UNIX_TIMESTAMP(date_retired) FROM location WHERE uuid='${LOCATION_UUID}'"

# Execute inside docker container
DB_RES=$(docker exec bahmni-openmrsdb mysql -u openmrs-user -ppassword openmrs -N -e "$DB_QUERY" 2>/dev/null)

# Parse DB results (Tab separated: retired_bit, reason, timestamp)
if [ -n "$DB_RES" ]; then
    DB_EXISTS="true"
    DB_RETIRED_VAL=$(echo "$DB_RES" | awk '{print $1}')
    # Extract reason (fields 2 to N-1)
    DB_REASON=$(echo "$DB_RES" | awk '{$1=""; $NF=""; print $0}' | sed 's/^ *//;s/ *$//')
    DB_TIMESTAMP=$(echo "$DB_RES" | awk '{print $NF}')
else
    DB_EXISTS="false"
    DB_RETIRED_VAL="0"
    DB_REASON=""
    DB_TIMESTAMP="0"
fi

# Map DB bit to boolean string
if [ "$DB_RETIRED_VAL" == "1" ]; then
    DB_RETIRED="true"
else
    DB_RETIRED="false"
fi

# 5. Construct Result JSON
# Use a temp file to avoid quoting issues
python3 -c "
import json
import os

result = {
    'task_start_ts': $TASK_START,
    'location_uuid': '$LOCATION_UUID',
    'initial_retired_state': '$INITIAL_RETIRED',
    'api_verification': {
        'exists': $API_EXISTS,
        'retired': $API_RETIRED,
        'reason': '$API_REASON'
    },
    'db_verification': {
        'exists': $DB_EXISTS,
        'retired': $DB_RETIRED,
        'reason': '$DB_REASON',
        'retire_timestamp': $DB_TIMESTAMP
    },
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="