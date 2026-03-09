#!/bin/bash
echo "=== Exporting Transcribe Complaint Result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Get the latest complaint created
echo "Fetching latest complaint..."
# We fetch all complaints and sort by created date (or just take the last one if default sort is time based)
# ArkCase API list returns array. We'll look for one created after task start time.

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
EXPECTED_PERSON_ID=$(cat /tmp/expected_person_id.txt 2>/dev/null || echo "")

# Fetch detailed list of complaints (assuming < 100 for this env)
API_RESULT_FILE="/tmp/complaints_dump.json"
arkcase_api GET "plugin/complaint?limit=50&sort=created&desc=true" > "$API_RESULT_FILE"

# 3. Check for PDF viewer usage
PDF_OPENED="false"
# Simple check if evince (gnome doc viewer) or similar ran.
# Since we can't easily check past processes, we check if it's currently open or we rely on VLM.
if pgrep -f "evince" > /dev/null || pgrep -f "document-viewer" > /dev/null; then
    PDF_OPENED="true"
fi

# 4. Extract Data using Python for reliability
python3 -c "
import json
import os
import sys

try:
    with open('$API_RESULT_FILE', 'r') as f:
        complaints = json.load(f)
    
    # Filter for complaints created recently (naive check: just take the top one if list is sorted desc)
    # Ideally we'd check timestamps, but let's assume the agent created the newest one.
    
    found = False
    result_data = {
        'complaint_found': False,
        'title': '',
        'description': '',
        'incident_date': '',
        'requestor_id': '',
        'requestor_name': ''
    }

    if complaints and isinstance(complaints, list) and len(complaints) > 0:
        # Get the most recent one
        latest = complaints[0]
        
        # We can also search for the specific title to be sure
        for c in complaints:
            if 'Construction' in c.get('complaintTitle', '') or 'Noise' in c.get('complaintTitle', ''):
                latest = c
                break
        
        result_data['complaint_found'] = True
        result_data['title'] = latest.get('complaintTitle', '')
        result_data['description'] = latest.get('details', '') or latest.get('description', '')
        result_data['incident_date'] = latest.get('incidentDate', '')
        
        # Requestor/Complainant field structure depends on ArkCase version
        # Often it's in 'complainant' object or 'requestor' object
        req = latest.get('complainant', {}) or latest.get('requestor', {})
        if not req and 'people' in latest:
             # Sometimes linked as a participant
             pass
             
        # If API structure is flat ID
        if not req:
             req_id = latest.get('complainantId')
             if req_id:
                 result_data['requestor_id'] = req_id

        # Try to extract name/id
        if isinstance(req, dict):
            result_data['requestor_id'] = req.get('id', '')
            result_data['requestor_name'] = f\"{req.get('firstName', '')} {req.get('lastName', '')}\".strip()

    # Save result
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result_data, f)
        
except Exception as e:
    print(f'Error processing result: {e}')
    # Write empty failure
    with open('/tmp/task_result.json', 'w') as f:
        json.dump({'complaint_found': False, 'error': str(e)}, f)
"

# 5. Append system checks to result
# We merge the python output with shell checks
TEMP_JSON=$(mktemp)
cat /tmp/task_result.json > "$TEMP_JSON"

# Add PDF opened status
jq --arg pdf "$PDF_OPENED" '. + {"pdf_viewer_opened": $pdf}' "$TEMP_JSON" > /tmp/task_result_final.json

# Move to final location
cp /tmp/task_result_final.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"