#!/bin/bash
# Export results for "create_security_incident" task
echo "=== Exporting Create Security Incident Results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Fetch Incidents via API
echo "Fetching incidents via API..."
API_RESPONSE=$(ela_api_call "/event/api/v2/incidents" "GET")

# 2. Backup: specific SQL query if API fails or is empty
# We search for the specific title in the database
echo "Querying database for incident..."
DB_SEARCH=$(ela_db_query "SELECT * FROM helpdesk_ticket WHERE title LIKE '%Brute Force Attempt%'" 2>/dev/null)
if [ -z "$DB_SEARCH" ]; then
    # Try alternate table names if 'helpdesk_ticket' isn't correct (schema fallback)
    DB_SEARCH=$(ela_db_query "SELECT * FROM arc_incident WHERE title LIKE '%Brute Force Attempt%'" 2>/dev/null)
fi

# 3. Get final incident count
FINAL_COUNT_RAW=$(echo "$API_RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    incidents = data.get('incidents', data.get('data', []))
    print(len(incidents))
except:
    print('0')
")

# 4. Check if a specific incident matching our criteria exists in the API response
# We parse the JSON to find the task-specific incident
MATCHING_INCIDENT=$(echo "$API_RESPONSE" | python3 -c "
import sys, json

expected_title = 'Brute Force Attempt on Service Accounts'
match_found = False
incident_details = {}

try:
    data = json.load(sys.stdin)
    incidents = data.get('incidents', data.get('data', []))
    
    for inc in incidents:
        # Check title (case insensitive partial match)
        title = inc.get('title', inc.get('subject', ''))
        if expected_title.lower() in title.lower():
            match_found = True
            incident_details = inc
            break
            
    print(json.dumps({'found': match_found, 'details': incident_details}))
except Exception as e:
    print(json.dumps({'found': False, 'error': str(e)}))
")

# 5. Take final screenshot
take_screenshot /tmp/task_final.png

# 6. Prepare result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_count": $(cat /tmp/initial_incident_count.txt 2>/dev/null || echo 0),
    "final_count": ${FINAL_COUNT_RAW:-0},
    "api_response_valid": $([ -n "$API_RESPONSE" ] && echo "true" || echo "false"),
    "db_record_found": $([ -n "$DB_SEARCH" ] && echo "true" || echo "false"),
    "matching_incident": $MATCHING_INCIDENT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move result to final location with permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export Complete ==="