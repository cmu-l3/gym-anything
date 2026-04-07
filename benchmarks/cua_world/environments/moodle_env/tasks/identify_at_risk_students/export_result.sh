#!/bin/bash
# Export script for Identify At-Risk Students task

echo "=== Exporting Task Results ==="

# Source utilities
. /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type moodle_query &>/dev/null; then
    _get_mariadb_method() { cat /tmp/mariadb_method 2>/dev/null || echo "native"; }
    moodle_query() {
        local query="$1"
        local method=$(_get_mariadb_method)
        if [ "$method" = "docker" ]; then
            docker exec moodle-mariadb mysql -u moodleuser -pmoodlepass moodle -N -B -e "$query" 2>/dev/null
        else
            mysql -u moodleuser -pmoodlepass moodle -N -B -e "$query" 2>/dev/null
        fi
    }
    moodle_query_headers() {
        local query="$1"
        local method=$(_get_mariadb_method)
        if [ "$method" = "docker" ]; then
            docker exec moodle-mariadb mysql -u moodleuser -pmoodlepass moodle -e "$query" 2>/dev/null
        else
            mysql -u moodleuser -pmoodlepass moodle -e "$query" 2>/dev/null
        fi
    }
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
ADMIN_ID=$(moodle_query "SELECT id FROM mdl_user WHERE username='admin'" | tr -d '[:space:]')

echo "Analyzing messages sent since $TASK_START by user $ADMIN_ID..."

# We need to find:
# 1. Messages sent by admin
# 2. After task start
# 3. Containing "catch up" (case-insensitive)
# 4. Who received them

# Get all relevant conversation messages
# Moodle 4.x messaging structure:
# mdl_message_messages (content, timecreated, useridfrom, conversationid)
# mdl_message_conversation_members (conversationid, userid)

# Step 1: Find message IDs and Conversation IDs matching criteria
# Note: timecreated is unix timestamp
MSG_QUERY="SELECT id, conversationid, fullmessage, timecreated 
           FROM mdl_message_messages 
           WHERE useridfrom=$ADMIN_ID 
           AND timecreated >= $TASK_START 
           AND LOWER(fullmessage) LIKE '%catch up%'"

RELEVANT_MSGS=$(moodle_query "$MSG_QUERY")

# Create JSON structure
JSON_OUTPUT="/tmp/messages_analysis.json"
echo "[" > "$JSON_OUTPUT"

FIRST=1
while IFS=$'\t' read -r mid cid content time; do
    if [ -z "$mid" ]; then continue; fi
    
    if [ "$FIRST" -eq 1 ]; then FIRST=0; else echo "," >> "$JSON_OUTPUT"; fi
    
    # Clean content for JSON
    clean_content=$(echo "$content" | sed 's/"/\\"/g' | tr -d '\n' | tr -d '\r')
    
    echo "  {" >> "$JSON_OUTPUT"
    echo "    \"message_id\": $mid," >> "$JSON_OUTPUT"
    echo "    \"conversation_id\": $cid," >> "$JSON_OUTPUT"
    echo "    \"content\": \"$clean_content\"," >> "$JSON_OUTPUT"
    echo "    \"time\": $time," >> "$JSON_OUTPUT"
    
    # Get recipients for this conversation (excluding admin)
    RECIP_QUERY="SELECT u.username 
                 FROM mdl_message_conversation_members mcm
                 JOIN mdl_user u ON mcm.userid = u.id
                 WHERE mcm.conversationid = $cid 
                 AND mcm.userid != $ADMIN_ID"
    
    RECIPIENTS=$(moodle_query "$RECIP_QUERY" | tr '\n' ',' | sed 's/,$//')
    
    # Convert comma list to JSON array
    JSON_RECIPS=$(echo "$RECIPIENTS" | awk -F, '{printf "["; for(i=1;i<=NF;i++) printf "\"%s\"%s", $i, (i==NF?"":","); printf "]"}')
    if [ -z "$JSON_RECIPS" ]; then JSON_RECIPS="[]"; fi
    
    echo "    \"recipients\": $JSON_RECIPS" >> "$JSON_OUTPUT"
    echo "  }" >> "$JSON_OUTPUT"
    
done <<< "$RELEVANT_MSGS"

echo "]" >> "$JSON_OUTPUT"

# Final JSON Result
FINAL_JSON="/tmp/task_result.json"
cat > "$FINAL_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "export_time": $(date +%s),
    "messages": $(cat $JSON_OUTPUT),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

echo "Export complete. Result:"
cat "$FINAL_JSON"