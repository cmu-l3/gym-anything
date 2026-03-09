#!/bin/bash
# Export script for Quarterly Data Review Message task

echo "=== Exporting Quarterly Data Review Message Result ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        curl -s -u admin:district "http://localhost:8080/api/$1"
    }
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

take_screenshot /tmp/task_end_screenshot.png

TASK_START_EPOCH=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_START_ISO=$(cat /tmp/task_start_iso 2>/dev/null || echo "2020-01-01T00:00:00")
INITIAL_MSG_COUNT=$(cat /tmp/initial_message_count 2>/dev/null || echo "0")

echo "Checking DHIS2 messages created after $TASK_START_ISO..."

# Query recent messages
# We fetch ID, subject, created time, sender, and recipient info
MSG_RESULT=$(dhis2_api "messageConversations?fields=id,created,subject,lastMessage,userGroupMessages,userMessages,messageCount&order=created:desc&pageSize=10" 2>/dev/null | \
python3 -c "
import json, sys
from datetime import datetime

try:
    data = json.load(sys.stdin)
    task_start_iso = '$TASK_START_ISO'
    # Simple ISO parsing (python 3.7+ supports fromisoformat, but we'll be robust)
    try:
        # Handle potential Z or offset issues roughly if needed, usually DHIS2 returns ISO
        task_start = datetime.fromisoformat(task_start_iso.replace('Z', '+00:00'))
    except:
        task_start = datetime(2025, 1, 1) # Fallback

    conversations = data.get('messageConversations', [])
    
    found_messages = []
    
    for conv in conversations:
        created_str = conv.get('created', '')
        # DHIS2 date format robustness
        try:
            # Replace Z with +00:00 for python isoformat compatibility
            fmt_created = created_str.replace('Z', '+00:00')
            # Fix +0000 to +00:00 if needed
            if len(fmt_created) > 5 and fmt_created[-5] in ['+', '-'] and ':' not in fmt_created[-5:]:
                 fmt_created = fmt_created[:-2] + ':' + fmt_created[-2:]
            
            created_dt = datetime.fromisoformat(fmt_created)
            
            if created_dt >= task_start:
                # Get recipients count
                ug_count = len(conv.get('userGroupMessages', []))
                u_count = len(conv.get('userMessages', []))
                
                # Verify body length is sufficient (checking 'lastMessage' usually contains the text)
                body_text = conv.get('lastMessage', '')
                
                found_messages.append({
                    'id': conv.get('id'),
                    'subject': conv.get('subject', ''),
                    'body_length': len(body_text),
                    'body_preview': body_text[:50],
                    'has_recipients': (ug_count + u_count) > 0,
                    'created': created_str
                })
        except Exception as e:
            # Skip if date parsing fails
            pass

    print(json.dumps({
        'new_messages_count': len(found_messages),
        'messages': found_messages,
        'initial_count': int('$INITIAL_MSG_COUNT')
    }))

except Exception as e:
    print(json.dumps({'error': str(e), 'new_messages_count': 0, 'messages': []}))
" 2>/dev/null || echo '{"new_messages_count": 0, "messages": []}')

# Check Local File
FILE_PATH="/home/ga/Desktop/bo_q4_2023_data_review_message.txt"
FILE_EXISTS="false"
FILE_SIZE=0
FILE_CONTENT_PREVIEW=""
FILE_CREATED_DURING_TASK="false"

if [ -f "$FILE_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$FILE_PATH")
    FILE_MTIME=$(stat -c %Y "$FILE_PATH")
    
    # Read first 100 chars safely
    FILE_CONTENT_PREVIEW=$(head -c 100 "$FILE_PATH" | tr -d '\0')
    
    if [ "$FILE_MTIME" -ge "$TASK_START_EPOCH" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Construct final JSON
cat > /tmp/quarterly_data_review_message_result.json << ENDJSON
{
    "task_start_iso": "$TASK_START_ISO",
    "dhis2_messages": $MSG_RESULT,
    "local_file": {
        "exists": $FILE_EXISTS,
        "path": "$FILE_PATH",
        "size_bytes": $FILE_SIZE,
        "created_during_task": $FILE_CREATED_DURING_TASK,
        "content_preview": "$FILE_CONTENT_PREVIEW"
    },
    "export_timestamp": "$(date -Iseconds)"
}
ENDJSON

echo "Result saved to /tmp/quarterly_data_review_message_result.json"
cat /tmp/quarterly_data_review_message_result.json
echo ""
echo "=== Export Complete ==="