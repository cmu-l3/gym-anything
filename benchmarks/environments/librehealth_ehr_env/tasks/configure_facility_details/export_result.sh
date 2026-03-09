#!/bin/bash
set -e
echo "=== Exporting Facility Configuration Results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 2. Capture final screenshot (visual evidence of completion)
take_screenshot /tmp/task_final.png

# 3. Query the database for the final state of Facility ID 1
# We fetch specific columns to verify against expected values
echo "Querying final facility data..."
DB_RESULT=$(librehealth_query "SELECT name, federal_ein, email, website, phone, billing_location FROM facility WHERE id=1")

# Parse the tab-separated DB result into variables
# Note: mysql -N produces tab-separated output without headers
IFS=$'\t' read -r NAME EIN EMAIL WEBSITE PHONE BILLING <<< "$DB_RESULT"

# Handle potential empty results if query failed
NAME=${NAME:-""}
EIN=${EIN:-""}
EMAIL=${EMAIL:-""}
WEBSITE=${WEBSITE:-""}
PHONE=${PHONE:-""}
BILLING=${BILLING:-"0"}

# 4. Check if values changed from initial state (Anti-gaming)
INITIAL_STATE=$(cat /tmp/initial_facility_state.txt 2>/dev/null || echo "")
if [ "$DB_RESULT" != "$INITIAL_STATE" ]; then
    DB_CHANGED="true"
else
    DB_CHANGED="false"
fi

# 5. Create JSON result file
# We use python to safely dump JSON to avoid escaping issues with special characters in names/urls
python3 -c "
import json
import sys

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'db_changed': $DB_CHANGED,
    'facility_data': {
        'name': sys.argv[1],
        'ein': sys.argv[2],
        'email': sys.argv[3],
        'website': sys.argv[4],
        'phone': sys.argv[5],
        'billing_location': sys.argv[6]
    }
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
" "$NAME" "$EIN" "$EMAIL" "$WEBSITE" "$PHONE" "$BILLING"

# Set permissions so the host can read it (if needed)
chmod 644 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json:"
cat /tmp/task_result.json
echo "=== Export Complete ==="