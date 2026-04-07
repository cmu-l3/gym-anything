#!/bin/bash
echo "=== Exporting implement_external_event_bookmarking result ==="

source /workspace/scripts/task_utils.sh

# Refresh token just in case
refresh_nx_token > /dev/null 2>&1 || true

TASK_START_TS=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# ==============================================================================
# 1. FETCH EVENT RULES
# ==============================================================================
echo "Fetching event rules..."
RULES_JSON=$(nx_api_get "/rest/v1/eventRules")

# ==============================================================================
# 2. FETCH BOOKMARKS
# ==============================================================================
echo "Fetching bookmarks..."
# We need the camera ID for "Parking Lot Camera"
CAM_ID=$(get_camera_id_by_name "Parking Lot Camera")

BOOKMARKS_JSON="[]"
if [ -n "$CAM_ID" ]; then
    # Fetch bookmarks from roughly the start time to now
    # Converting TS to ms for API if needed, or just get last 20
    # The API standard is usually milliseconds for startTime
    START_MS=$(($TASK_START_TS * 1000))
    # Nx Witness API for bookmarks often takes startTimeMs
    BOOKMARKS_JSON=$(nx_api_get "/rest/v1/devices/$CAM_ID/bookmarks?startTimeMs=$START_MS")
else
    echo "Error: Parking Lot Camera ID not found during export"
fi

# ==============================================================================
# 3. COMPILE RESULT JSON
# ==============================================================================

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create a temporary python script to structure the data safely
cat > /tmp/process_results.py << EOF
import json
import sys
import time

try:
    rules_raw = sys.argv[1]
    bookmarks_raw = sys.argv[2]
    task_start = int(sys.argv[3])
    
    rules = json.loads(rules_raw) if rules_raw else []
    bookmarks = json.loads(bookmarks_raw) if bookmarks_raw else []
    
    # Analyze Rules
    found_rule = False
    rule_correct = False
    
    for r in rules:
        # Check if it's a generic event
        # Nx Witness internal type for generic event is 'software.nx.event.generic'
        event_type = r.get('eventType', '')
        
        # Check condition (source/caption are often encoded in eventCondition or separate fields depending on version)
        # Usually stored as a resource param or condition string
        # For simplicity, we check if the raw json string of the rule contains our keywords,
        # verifying the specific fields where possible.
        rule_str = json.dumps(r)
        
        if 'software.nx.event.generic' in event_type:
            # Check for keywords in the condition/params
            has_source = 'AI_Analytics' in rule_str
            has_caption = 'Loitering_Detected' in rule_str
            
            # Check action
            action_type = r.get('actionType', '')
            is_bookmark = 'cameraBookmark' in action_type or 'bookmark' in action_type.lower()
            
            # Check target (camera ID) - handled by verifier logic, we just dump the data
            
            if has_source and has_caption and is_bookmark:
                found_rule = True
                rule_correct = True
                break
                
    # Analyze Bookmarks
    found_bookmark = False
    bookmark_details = {}
    
    for b in bookmarks:
        # Check name/description
        name = b.get('name', '')
        desc = b.get('description', '')
        
        if 'Loitering_Detected' in name or 'Loitering_Detected' in desc:
            # Check creation time (creationTimeMs or startTimeMs)
            b_time = int(b.get('startTimeMs', 0)) / 1000
            if b_time > task_start:
                found_bookmark = True
                bookmark_details = b
                break
    
    result = {
        "task_start_ts": task_start,
        "rules_data": rules,
        "bookmarks_data": bookmarks,
        "analysis": {
            "found_valid_rule": rule_correct,
            "found_valid_bookmark": found_bookmark,
            "bookmark_details": bookmark_details
        },
        "target_camera_id": "$CAM_ID"
    }
    
    print(json.dumps(result, indent=2))
    
except Exception as e:
    print(json.dumps({"error": str(e)}))

EOF

# Execute python script
python3 /tmp/process_results.py "$RULES_JSON" "$BOOKMARKS_JSON" "$TASK_START_TS" > /tmp/task_result.json

# Cleanup
rm -f /tmp/process_results.py

echo "Export complete. Result:"
head -n 20 /tmp/task_result.json