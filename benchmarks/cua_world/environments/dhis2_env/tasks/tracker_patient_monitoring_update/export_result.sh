#!/bin/bash
# Export script for Tracker Patient Monitoring Update task

echo "=== Exporting Tracker Update Result ==="

source /workspace/scripts/task_utils.sh

dhis2_api_get() {
    curl -s -u admin:district "http://localhost:8080/api/$1"
}

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Retrieve IDs
TEI_ID=$(cat /tmp/target_tei_id.txt 2>/dev/null)
PROG_ID=$(cat /tmp/target_prog_id.txt 2>/dev/null)
PHONE_ATTR_ID=$(cat /tmp/target_phone_attr_id.txt 2>/dev/null)
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Checking TEI: $TEI_ID"

# 3. Query TEI Attributes (Phone Number)
echo "Querying attributes..."
TEI_DATA=$(dhis2_api_get "trackedEntityInstances/$TEI_ID?fields=attributes[attribute,value]")
PHONE_VALUE=$(echo "$TEI_DATA" | jq -r --arg ATTR "$PHONE_ATTR_ID" '.attributes[] | select(.attribute == $ATTR) | .value')
echo "Phone Value found: $PHONE_VALUE"

# 4. Query Enrollments (Events and Notes)
# We need to look at the active enrollment in the program
echo "Querying enrollments..."
ENROLLMENT_DATA=$(dhis2_api_get "enrollments?trackedEntityInstance=$TEI_ID&program=$PROG_ID&fields=enrollment,notes,events[event,status,dueDate,programStage]")

# Extract Notes
# Notes in DHIS2 API are usually inside the enrollment object
NOTES_JSON=$(echo "$ENROLLMENT_DATA" | jq -c '.enrollments[0].notes // []')
echo "Notes found: $NOTES_JSON"

# Extract Events
# We are looking for a SCHEDULED event in the future
EVENTS_JSON=$(echo "$ENROLLMENT_DATA" | jq -c '.enrollments[0].events // []')
echo "Events found count: $(echo "$EVENTS_JSON" | jq length)"

# 5. Construct Result JSON
JSON_OUTPUT="/tmp/task_result.json"

# Create a temporary python script to format the JSON correctly to avoid bash escaping hell
cat <<EOF > /tmp/format_result.py
import json
import time

try:
    phone = "$PHONE_VALUE"
    notes_raw = '$NOTES_JSON'
    events_raw = '$EVENTS_JSON'
    task_start = $TASK_START_TIME

    notes = json.loads(notes_raw) if notes_raw else []
    events = json.loads(events_raw) if events_raw else []

    # Check for specific note content
    note_found = False
    for note in notes:
        # Notes might not have a timestamp in simple view, or we assume it was added recently if it matches text
        if "planning travel" in note.get('value', '').lower():
            note_found = True

    # Check for scheduled event
    scheduled_event_found = False
    scheduled_date = ""
    for event in events:
        if event.get('status') == 'SCHEDULE':
            # Check if it was updated/created recently? 
            # DHIS2 events have 'created' and 'lastUpdated' fields but we didn't fetch them specifically above
            # For simplicity, we just check if a scheduled event exists for the target date in verifier
            scheduled_event_found = True
            scheduled_date = event.get('dueDate', '')

    result = {
        "tei_id": "$TEI_ID",
        "phone_value": phone,
        "note_found_text": note_found,
        "all_notes": notes,
        "events": events,
        "task_start": task_start,
        "timestamp": time.time()
    }
    
    print(json.dumps(result, indent=2))

except Exception as e:
    print(json.dumps({"error": str(e)}))
EOF

python3 /tmp/format_result.py > "$JSON_OUTPUT"

# Permission fix
chmod 666 "$JSON_OUTPUT" 2>/dev/null || sudo chmod 666 "$JSON_OUTPUT" 2>/dev/null || true

echo "Result JSON generated:"
cat "$JSON_OUTPUT"

echo "=== Export Complete ==="