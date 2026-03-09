#!/bin/bash
echo "=== Exporting Create Appointment Service Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Get Task Start Time
TASK_START_TIMESTAMP=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END_TIMESTAMP=$(date +%s)

# 3. Query OpenMRS API for the service
echo "Querying API for 'Nutrition Counseling'..."
API_RESPONSE=$(openmrs_api_get "/appointmentscheduling/service?q=Nutrition&v=full")

# 4. Parse the response using Python to extract specific fields safely
# We look for an exact name match in the results
read -r SERVICE_FOUND SERVICE_UUID SERVICE_NAME SERVICE_DURATION SERVICE_DESC SERVICE_DATE_CREATED <<EOF
$(echo "$API_RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    results = data.get('results', [])
    found = False
    uuid = ''
    name = ''
    duration = 0
    desc = ''
    date_created = ''
    
    # Filter for exact name match (API search is fuzzy)
    for s in results:
        if s.get('name', '').strip() == 'Nutrition Counseling':
            found = True
            uuid = s.get('uuid', '')
            name = s.get('name', '')
            duration = s.get('durationMins', 0)
            desc = s.get('description', '')
            # auditInfo might be nested or direct depending on API version
            audit = s.get('auditInfo', {})
            date_created = audit.get('dateCreated', '')
            break
            
    print(f'{str(found).lower()} {uuid} {name.replace(' ', '_')} {duration} {desc.replace(' ', '_')} {date_created}')
except Exception as e:
    print(f'false error error 0 error error')
")
EOF

# Restore spaces in description and name (replaced with _ for simple shell reading)
SERVICE_NAME=$(echo "$SERVICE_NAME" | tr '_' ' ')
SERVICE_DESC=$(echo "$SERVICE_DESC" | tr '_' ' ')

echo "Found: $SERVICE_FOUND"
echo "Name: $SERVICE_NAME"
echo "Duration: $SERVICE_DURATION"

# 5. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START_TIMESTAMP,
    "task_end_timestamp": $TASK_END_TIMESTAMP,
    "service_found": $SERVICE_FOUND,
    "service_uuid": "$SERVICE_UUID",
    "service_name": "$SERVICE_NAME",
    "service_duration": $SERVICE_DURATION,
    "service_description": "$SERVICE_DESC",
    "service_date_created": "$SERVICE_DATE_CREATED",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 6. Save result with correct permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="