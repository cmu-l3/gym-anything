#!/bin/bash
echo "=== Exporting create_custom_tracker results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get Admin API Key
ADMIN_API_KEY=$(redmine_admin_api_key)
# Fallback if jq/file fail
if [ -z "$ADMIN_API_KEY" ] || [ "$ADMIN_API_KEY" == "null" ]; then
    # Try default admin/admin basic auth if key missing (often works in dev envs)
    AUTH_HEADER="Authorization: Basic $(echo -n 'admin:Admin1234!' | base64)"
else
    AUTH_HEADER="X-Redmine-API-Key: $ADMIN_API_KEY"
fi

echo "Extracting data from Redmine API..."

# 1. Get All Trackers
# We need to find the one named "Permit Application"
TRACKERS_JSON=$(curl -s -H "$AUTH_HEADER" "$REDMINE_BASE_URL/trackers.json")
echo "$TRACKERS_JSON" > /tmp/trackers_dump.json

# Extract our specific tracker ID if it exists
TRACKER_ID=$(echo "$TRACKERS_JSON" | jq -r '.trackers[] | select(.name == "Permit Application") | .id' | head -n 1)

# 2. Get Issues
# Filter by subject containing "Wind Farm Alpha" to find the candidate issue
# We fetch list and filter manually in jq to be safe
ISSUES_JSON=$(curl -s -H "$AUTH_HEADER" "$REDMINE_BASE_URL/issues.json?limit=100")
echo "$ISSUES_JSON" > /tmp/issues_dump.json

# Prepare Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

# We construct the JSON using python for reliability in complex logic
python3 -c "
import json
import os
import sys

try:
    task_start = int('$TASK_START')
    task_end = int('$TASK_END')

    # Load trackers
    with open('/tmp/trackers_dump.json', 'r') as f:
        trackers_data = json.load(f)
    
    target_tracker = next((t for t in trackers_data.get('trackers', []) if t['name'] == 'Permit Application'), None)
    
    tracker_found = False
    tracker_info = {}
    
    if target_tracker:
        tracker_found = True
        tracker_info = target_tracker
        # Note: API doesn't always return creation time for trackers, but we can infer from ID > initial state if needed
        # or rely on the fact it wasn't there before (assumed for unique name)

    # Load issues
    with open('/tmp/issues_dump.json', 'r') as f:
        issues_data = json.load(f)
        
    # Find our issue
    # Criteria: Subject contains 'Wind Farm Alpha' AND 'Permit'
    target_issue = next((i for i in issues_data.get('issues', []) 
                        if 'Wind Farm Alpha' in i['subject'] 
                        and 'Permit' in i['subject']), None)
    
    issue_found = False
    issue_info = {}
    issue_created_during_task = False
    
    if target_issue:
        issue_found = True
        issue_info = target_issue
        
        # Check timestamp
        created_on = target_issue.get('created_on', '')
        # format: 2023-10-27T10:00:00Z
        if created_on:
            from datetime import datetime
            # simple parse
            try:
                dt = datetime.strptime(created_on, '%Y-%m-%dT%H:%M:%SZ')
                ts = dt.timestamp()
                if ts >= task_start - 60: # buffer for clock skew
                    issue_created_during_task = True
            except:
                pass

    result = {
        'task_start': task_start,
        'task_end': task_end,
        'tracker_found': tracker_found,
        'tracker_info': tracker_info,
        'issue_found': issue_found,
        'issue_info': issue_info,
        'issue_created_during_task': issue_created_during_task,
        'screenshot_path': '/tmp/task_final.png'
    }
    
    print(json.dumps(result))

except Exception as e:
    print(json.dumps({'error': str(e)}))

" > "$TEMP_JSON"

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="