#!/bin/bash
echo "=== Exporting bulk_assign_conversations result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Read the IDs we are tracking
if [ ! -f /tmp/target_conversation_ids.txt ]; then
    echo "ERROR: Target conversation IDs file not found!"
    exit 1
fi

TARGET_IDS=$(cat /tmp/target_conversation_ids.txt)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULTS_JSON="["

FIRST=true
for CID in $TARGET_IDS; do
    if [ "$FIRST" = true ]; then
        FIRST=false
    else
        RESULTS_JSON="$RESULTS_JSON,"
    fi
    
    # Query details for this conversation
    # user_id, status, updated_at
    # Join with users table to get assignee email/name if assigned
    QUERY="SELECT c.id, c.subject, c.status, c.user_id, c.updated_at, u.first_name, u.last_name, u.email 
           FROM conversations c 
           LEFT JOIN users u ON c.user_id = u.id 
           WHERE c.id = $CID"
    
    DATA=$(fs_query "$QUERY")
    
    # Parse results (tab separated)
    # Default values
    ID="$CID"
    SUBJECT=""
    STATUS=""
    USER_ID="NULL"
    UPDATED_AT=""
    U_FIRST=""
    U_LAST=""
    U_EMAIL=""
    
    if [ -n "$DATA" ]; then
        ID=$(echo "$DATA" | cut -f1)
        SUBJECT=$(echo "$DATA" | cut -f2)
        STATUS=$(echo "$DATA" | cut -f3)
        USER_ID=$(echo "$DATA" | cut -f4)
        UPDATED_AT=$(echo "$DATA" | cut -f5)
        U_FIRST=$(echo "$DATA" | cut -f6)
        U_LAST=$(echo "$DATA" | cut -f7)
        U_EMAIL=$(echo "$DATA" | cut -f8)
    fi
    
    # Check if updated after task start
    UPDATED_TS=$(date -d "$UPDATED_AT" +%s 2>/dev/null || echo "0")
    WAS_UPDATED="false"
    if [ "$UPDATED_TS" -gt "$TASK_START" ]; then
        WAS_UPDATED="true"
    fi
    
    # JSON Escape
    SUBJECT_ESC=$(echo "$SUBJECT" | sed 's/"/\\"/g')
    U_FIRST_ESC=$(echo "$U_FIRST" | sed 's/"/\\"/g')
    U_LAST_ESC=$(echo "$U_LAST" | sed 's/"/\\"/g')
    
    RESULTS_JSON="$RESULTS_JSON {
        \"id\": $ID,
        \"subject\": \"$SUBJECT_ESC\",
        \"status\": \"$STATUS\",
        \"user_id\": \"$USER_ID\",
        \"assignee_email\": \"$U_EMAIL\",
        \"assignee_name\": \"$U_FIRST_ESC $U_LAST_ESC\",
        \"was_updated\": $WAS_UPDATED
    }"
done

RESULTS_JSON="$RESULTS_JSON]"

# Write to file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
echo "$RESULTS_JSON" > "$TEMP_JSON"
safe_write_result "$TEMP_JSON" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="