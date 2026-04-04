#!/bin/bash
echo "=== Exporting add_note_to_conversation result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Load Task Context
CONV_SUBJECT="VPN connection drops intermittently from Building C"
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_START_TS=$(cat /tmp/task_start_timestamp.txt 2>/dev/null || echo "1970-01-01 00:00:00")

# 1. Find the conversation
CONV_DATA=$(find_conversation_by_subject "$CONV_SUBJECT")
CONV_ID=""
CONV_FOUND="false"

if [ -n "$CONV_DATA" ]; then
    CONV_FOUND="true"
    CONV_ID=$(echo "$CONV_DATA" | cut -f1)
fi

echo "Conversation Found: $CONV_FOUND (ID: $CONV_ID)"

# 2. Analyze Threads
# We need to find threads created AFTER the task started for this conversation
# FreeScout Thread Types: 1=Customer Message, 2=Internal Note, 3=Reply to Customer

NEW_NOTE_FOUND="false"
NEW_REPLY_FOUND="false"
NOTE_BODY=""
NOTE_ID=""

if [ "$CONV_FOUND" = "true" ]; then
    # Get all threads for this conversation created after task start
    # Note: timestamps in DB might be UTC, check local environment match
    # We select ID, TYPE, BODY, CREATED_AT
    
    # Simple query to get the latest thread
    LATEST_THREAD=$(fs_query "SELECT id, type, body, created_at FROM threads WHERE conversation_id = $CONV_ID ORDER BY id DESC LIMIT 1" 2>/dev/null)
    
    if [ -n "$LATEST_THREAD" ]; then
        THREAD_ID=$(echo "$LATEST_THREAD" | cut -f1)
        THREAD_TYPE=$(echo "$LATEST_THREAD" | cut -f2)
        THREAD_BODY=$(echo "$LATEST_THREAD" | cut -f3)
        THREAD_CREATED=$(echo "$LATEST_THREAD" | cut -f4)
        
        # Convert DB timestamp to seconds for comparison
        THREAD_TS=$(date -d "$THREAD_CREATED" +%s 2>/dev/null || echo "0")
        
        echo "Latest Thread ID: $THREAD_ID, Type: $THREAD_TYPE, Created: $THREAD_CREATED ($THREAD_TS)"
        echo "Task Start: $TASK_START_TIME"

        # Check if created during task (with 10s buffer for clock skew)
        if [ "$THREAD_TS" -ge "$((TASK_START_TIME - 10))" ]; then
            if [ "$THREAD_TYPE" == "2" ]; then
                NEW_NOTE_FOUND="true"
                NOTE_BODY="$THREAD_BODY"
                NOTE_ID="$THREAD_ID"
            elif [ "$THREAD_TYPE" == "3" ]; then
                NEW_REPLY_FOUND="true"
                NOTE_BODY="$THREAD_BODY" # Captured to show what was sent wrongly
            fi
        else
            echo "Latest thread is too old (pre-task)."
        fi
    fi
fi

# Escape body for JSON
NOTE_BODY_ESC=$(echo "$NOTE_BODY" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' | sed 's/^"//;s/"$//')

# Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "conversation_found": $CONV_FOUND,
    "conversation_id": "$CONV_ID",
    "new_note_found": $NEW_NOTE_FOUND,
    "new_reply_found": $NEW_REPLY_FOUND,
    "note_body": "$NOTE_BODY_ESC",
    "note_id": "$NOTE_ID",
    "task_start_ts": "$TASK_START_TS",
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="