#!/bin/bash
echo "=== Exporting Create Appointment Service Result ==="
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final state screenshot
take_screenshot /tmp/task_final.png

# 1. Query the REST API for the specific service name
echo "Querying API for 'Ergonomic Assessment'..."
API_RESPONSE=$(omrs_get "/appointmentscheduling/appointmenttype?q=Ergonomic+Assessment&v=full")

# Save raw response for debugging
echo "$API_RESPONSE" > /tmp/api_response.json

# Extract details using Python
# We look for ANY non-retired service matching the name
read -r SERVICE_FOUND SERVICE_UUID SERVICE_DURATION SERVICE_DESC SERVICE_DATE_CREATED <<< $(python3 -c "
import sys, json, datetime

try:
    data = json.load(open('/tmp/api_response.json'))
    results = data.get('results', [])
    
    # Filter for exact name match and not retired
    target = next((r for r in results if r.get('name', '').lower() == 'ergonomic assessment' and not r.get('retired')), None)
    
    if target:
        uuid = target.get('uuid', '')
        duration = target.get('duration', 0)
        desc = target.get('description', '')
        
        # Parse date created (e.g., 2023-10-25T10:00:00.000+0000)
        # We just return the string for bash to handle or pass to verifier
        date_created = target.get('auditInfo', {}).get('dateCreated', '')
        
        print(f'true {uuid} {duration} {desc} {date_created}')
    else:
        print('false null 0 null null')
except Exception as e:
    print('false null 0 null null')
")

# 2. Database Verification (Double Check)
# This confirms persistence and allows checking timestamp if API date parsing is tricky
echo "Querying Database..."
DB_COUNT=$(omrs_db_query "SELECT count(*) FROM appointmentscheduling_appointment_type WHERE name='Ergonomic Assessment' AND duration_mins=45 AND retired=0;")

# 3. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "service_found": $SERVICE_FOUND,
    "service_uuid": "$SERVICE_UUID",
    "service_duration": $SERVICE_DURATION,
    "service_description": "$SERVICE_DESC",
    "service_date_created_iso": "$SERVICE_DATE_CREATED",
    "db_exact_match_count": ${DB_COUNT:-0},
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="