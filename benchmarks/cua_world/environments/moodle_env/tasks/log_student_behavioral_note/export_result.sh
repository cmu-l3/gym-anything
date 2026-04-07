#!/bin/bash
# Export script for Log Student Behavioral Note task

echo "=== Exporting Log Student Note Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Read IDs
USER_ID=$(cat /tmp/target_user_id 2>/dev/null || echo "0")
COURSE_ID=$(cat /tmp/target_course_id 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

echo "Checking notes for User $USER_ID in Course $COURSE_ID created after $TASK_START..."

# Query for the specific note created during the task
# We look for notes created/modified recently for this user
# Moodle stores notes in 'mdl_note'
# Fields: id, userid (student), courseid, content, format, created, lastmodified, usermodified, publishstate
# publishstate: 'personal' (I only), 'course' (Course teachers), 'site' (Site teachers)

NOTE_QUERY="SELECT id, content, publishstate, created, lastmodified 
            FROM mdl_note 
            WHERE userid=$USER_ID 
            AND courseid=$COURSE_ID 
            AND (created >= $TASK_START OR lastmodified >= $TASK_START)
            ORDER BY id DESC LIMIT 1"

NOTE_DATA=$(moodle_query "$NOTE_QUERY")

NOTE_FOUND="false"
NOTE_CONTENT=""
NOTE_STATE=""
NOTE_CREATED="0"

if [ -n "$NOTE_DATA" ]; then
    NOTE_FOUND="true"
    NOTE_ID=$(echo "$NOTE_DATA" | cut -f1)
    NOTE_CONTENT=$(echo "$NOTE_DATA" | cut -f2)
    NOTE_STATE=$(echo "$NOTE_DATA" | cut -f3)
    NOTE_CREATED=$(echo "$NOTE_DATA" | cut -f4)
    
    echo "Note found! ID: $NOTE_ID"
    echo "Content: $NOTE_CONTENT"
    echo "State: $NOTE_STATE"
else
    echo "No new note found matching criteria."
fi

# Also check for notes with wrong context (e.g. 'personal' or 'site') or wrong course
# ensuring we capture partial efforts
if [ "$NOTE_FOUND" = "false" ]; then
    echo "Checking for notes in wrong context/course..."
    # Check notes for user regardless of course
    ANY_NOTE=$(moodle_query "SELECT id, courseid, publishstate FROM mdl_note WHERE userid=$USER_ID AND created >= $TASK_START LIMIT 1")
    if [ -n "$ANY_NOTE" ]; then
        echo "Found a note but possibly wrong parameters: $ANY_NOTE"
    fi
fi

# Escape content for JSON
# Use python for safe escaping to avoid bash string hell
NOTE_CONTENT_JSON=$(python3 -c "import json, sys; print(json.dumps(sys.argv[1]))" "$NOTE_CONTENT")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/log_note_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "user_id": $USER_ID,
    "course_id": $COURSE_ID,
    "note_found": $NOTE_FOUND,
    "note_content": $NOTE_CONTENT_JSON,
    "publish_state": "$NOTE_STATE",
    "created_timestamp": $NOTE_CREATED,
    "task_start_timestamp": $TASK_START,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/log_note_result.json

echo ""
cat /tmp/log_note_result.json
echo ""
echo "=== Export Complete ==="