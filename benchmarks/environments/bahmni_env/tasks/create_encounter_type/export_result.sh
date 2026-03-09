#!/bin/bash
set -u

echo "=== Exporting Create Encounter Type Result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot (evidence of UI state)
take_screenshot /tmp/task_final.png

# 2. Get task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)

# 3. Query OpenMRS API for the created encounter type
# We search specifically for the name requested in the task
echo "Querying OpenMRS API for 'Telehealth Consultation'..."
API_RESPONSE=$(openmrs_api_get "/encountertype?q=Telehealth+Consultation&v=full")

# 4. Extract details using jq
# Note: q=SearchTerm returns partial matches, so we filter for exact name in verifier or here
# We save the raw API response for the verifier to parse robustly
echo "$API_RESPONSE" > /tmp/api_response.json

# 5. Check if we found it and extract basic info for log
FOUND_UUID=$(echo "$API_RESPONSE" | jq -r '.results[] | select(.name == "Telehealth Consultation") | .uuid' 2>/dev/null | head -1)

RESULT_EXISTS="false"
CREATED_DURING_TASK="false"
CREATION_DATE=""

if [ -n "$FOUND_UUID" ] && [ "$FOUND_UUID" != "null" ]; then
    RESULT_EXISTS="true"
    
    # Extract creation date from API response (Format: "2023-10-27T10:00:00.000+0000")
    DATE_STR=$(echo "$API_RESPONSE" | jq -r ".results[] | select(.uuid == \"$FOUND_UUID\") | .auditInfo.dateCreated" 2>/dev/null)
    CREATION_DATE="$DATE_STR"
    
    # Convert ISO date to unix timestamp for comparison
    # We use python for robust ISO parsing as date command varies
    CREATED_TS=$(python3 -c "
from datetime import datetime
import sys
try:
    dt_str = '$DATE_STR'
    # Handle Java SimpleDateFormat output often used in OpenMRS REST
    # It might be ISO8601 or similar. 
    # OpenMRS REST usually returns: '2025-03-01T18:35:00.000+0000'
    dt = datetime.strptime(dt_str, '%Y-%m-%dT%H:%M:%S.000%z')
    print(int(dt.timestamp()))
except Exception as e:
    print(0)
" 2>/dev/null || echo "0")
    
    # Allow a small buffer (clock skew)
    if [ "$CREATED_TS" -ge "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    else
        echo "WARNING: Encounter type exists but creation time ($CREATED_TS) < task start ($TASK_START)"
    fi
fi

# 6. Check if browser is running
BROWSER_RUNNING="false"
if pgrep -f "epiphany" > /dev/null; then
    BROWSER_RUNNING="true"
fi

# 7. Create JSON result
# We save the full API response inside the result for the Python verifier to inspect descriptions
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $CURRENT_TIME,
    "encounter_type_exists": $RESULT_EXISTS,
    "created_during_task": $CREATED_DURING_TASK,
    "creation_date_iso": "$CREATION_DATE",
    "found_uuid": "$FOUND_UUID",
    "browser_running": $BROWSER_RUNNING,
    "api_response": $(cat /tmp/api_response.json),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
echo "=== Export Complete ==="