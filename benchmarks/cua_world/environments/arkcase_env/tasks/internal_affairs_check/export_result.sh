#!/bin/bash
echo "=== Exporting Internal Affairs Check Result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record End Time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Load Ground Truth
if [ -f "/var/lib/arkcase/ground_truth/info.json" ]; then
    CASE_ID=$(grep -o '"case_id": *"[^"]*"' /var/lib/arkcase/ground_truth/info.json | cut -d'"' -f4)
    KEYWORD=$(grep -o '"keyword": *"[^"]*"' /var/lib/arkcase/ground_truth/info.json | cut -d'"' -f4)
else
    echo "ERROR: Ground truth file missing!"
    CASE_ID=""
fi

echo "Querying API for Case ID: $CASE_ID"

# API Query for Final State
# 1. Get Case Details (Priority)
CASE_JSON="{}"
if [ -n "$CASE_ID" ] && [ "$CASE_ID" != "UNKNOWN" ]; then
    CASE_JSON=$(arkcase_api GET "plugin/complaint/$CASE_ID")
fi

# 2. Get Case Notes
NOTES_JSON="[]"
if [ -n "$CASE_ID" ] && [ "$CASE_ID" != "UNKNOWN" ]; then
    # Try typical notes endpoint, fallback to fetching from main object if embedded
    NOTES_RES=$(arkcase_api GET "plugin/complaint/$CASE_ID/notes")
    if echo "$NOTES_RES" | grep -q "notes"; then
        NOTES_JSON="$NOTES_RES"
    else
        # If notes are embedded in main case object or different structure
        NOTES_JSON=$(arkcase_api GET "common/notes/complaint/$CASE_ID")
    fi
fi

# 3. Check App State
APP_RUNNING="false"
if pgrep -f "firefox" > /dev/null; then
    APP_RUNNING="true"
fi

# 4. Compile Result JSON
# We use python to safely construct JSON to avoid escaping issues
python3 -c "
import json, sys, time

try:
    case_data = json.loads('''$CASE_JSON''' or '{}')
    notes_data = json.loads('''$NOTES_JSON''' or '[]')
    
    # Extract priority
    final_priority = case_data.get('priority', 'Unknown')
    
    # Check notes for keyword
    keyword = '$KEYWORD'.lower()
    note_found = False
    note_content = ''
    
    # Handle different notes API structures (list vs dict with list)
    notes_list = notes_data if isinstance(notes_data, list) else notes_data.get('notes', [])
    
    for note in notes_list:
        text = note.get('text', '') or note.get('content', '') or ''
        if keyword in text.lower():
            note_found = True
            note_content = text
            break
            
    result = {
        'task_start': $TASK_START,
        'task_end': $TASK_END,
        'case_id': '$CASE_ID',
        'final_priority': final_priority,
        'note_added': note_found,
        'note_content_sample': note_content,
        'app_was_running': $APP_RUNNING,
        'screenshot_path': '/tmp/task_final.png'
    }
    
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f, indent=4)
        
except Exception as e:
    print(f'Error constructing result JSON: {e}')
    # Fallback JSON
    with open('/tmp/task_result.json', 'w') as f:
        json.dump({'error': str(e)}, f)
"

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="