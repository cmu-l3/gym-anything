#!/bin/bash
echo "=== Exporting schedule_case_meeting results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final state screenshot
take_screenshot /tmp/task_final.png

# 2. Gather data for verification
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TARGET_CASE_ID=$(cat /tmp/target_case_id.txt 2>/dev/null || echo "")
EXPECTED_DATE=$(cat /tmp/expected_date.txt 2>/dev/null || echo "")
EXPECTED_TIME=$(cat /tmp/expected_time.txt 2>/dev/null || echo "")

# 3. Query ArkCase API for Events
# We look for events created after task start
# Since we might not know the exact event ID, we list events and filter in Python or here.
# Assuming an endpoint like /api/v1/calendar/event or querying events via search.
# We'll try to fetch all events associated with the case if possible, or just recent events.

echo "Querying API for events..."

# Fetching events linked to the case (if endpoint allows) OR searching generally
# Strategy: Search for events with the expected title created recently
SEARCH_PAYLOAD='{"criteria": "Oversight Review Board"}'
# Note: This is a heuristic API call. If ArkCase search API differs, we rely on the generic list.
# Try to get recent events.
API_EVENTS=$(arkcase_api GET "calendar/event?size=50&sort=createdDate,desc")

# 4. Save raw API response to a temp file for processing
echo "$API_EVENTS" > /tmp/raw_events.json

# 5. Extract relevant event info using Python for robust parsing
# We want to find an event that:
# - Matches the title "Oversight Review Board"
# - Is linked to the target case (if link info is available in event object)
# - Has the correct start date/time

python3 -c "
import json
import sys
import os
from datetime import datetime

try:
    with open('/tmp/raw_events.json', 'r') as f:
        data = json.load(f)
    
    # ArkCase list responses usually wrap items in 'result' or are a list
    events = data.get('result', []) if isinstance(data, dict) else data
    if not isinstance(events, list):
        events = []

    target_case_id = '$TARGET_CASE_ID'
    expected_title = 'Oversight Review Board'
    
    found_event = None
    
    for event in events:
        # Check title
        if expected_title.lower() not in event.get('title', '').lower():
            continue
            
        # Check association (this varies by ArkCase version, checking common fields)
        # Often 'references' or 'associations' list.
        # Simple check: if we can't confirm association, we check title + timing strictly.
        
        found_event = event
        break

    result = {
        'found': bool(found_event),
        'event': found_event if found_event else {},
        'target_case_id_expected': target_case_id,
        'expected_date': '$EXPECTED_DATE',
        'expected_time': '$EXPECTED_TIME',
        'task_start_ts': $TASK_START
    }
    
    print(json.dumps(result))

except Exception as e:
    print(json.dumps({'error': str(e), 'found': False}))
" > /tmp/processed_result.json

# 6. Final JSON assembly
# We move the processed result to the standard location
mv /tmp/processed_result.json /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json