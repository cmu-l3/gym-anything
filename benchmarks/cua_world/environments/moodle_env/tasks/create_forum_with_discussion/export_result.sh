#!/bin/bash
# Export script for Create Forum with Discussion task

echo "=== Exporting Create Forum Result ==="

# Source shared utilities
. /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type moodle_query &>/dev/null; then
    echo "Warning: task_utils.sh functions not available, using inline definitions"
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
    take_screenshot() {
        local output_file="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 import -window root "$output_file" 2>/dev/null || echo "Could not take screenshot"
    }
    safe_write_json() {
        local temp_file="$1"; local dest_path="$2"
        rm -f "$dest_path" 2>/dev/null || true
        cp "$temp_file" "$dest_path"; chmod 666 "$dest_path" 2>/dev/null || true
        rm -f "$temp_file"; echo "Result saved to $dest_path"
    }
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Retrieve stored course ID and baseline
COURSE_ID=$(cat /tmp/target_course_id 2>/dev/null || echo "0")
INITIAL_FORUM_COUNT=$(cat /tmp/initial_forum_count 2>/dev/null || echo "0")
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Get current forum count
CURRENT_FORUM_COUNT="0"
if [ "$COURSE_ID" != "0" ]; then
    CURRENT_FORUM_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_forum WHERE course=$COURSE_ID" | tr -d '[:space:]')
fi
CURRENT_FORUM_COUNT=${CURRENT_FORUM_COUNT:-0}

echo "Forum count: initial=$INITIAL_FORUM_COUNT, current=$CURRENT_FORUM_COUNT"

# Search for the specific forum by name pattern
# Looking for "Clinical Case Study Discussions"
FORUM_DATA=$(moodle_query "SELECT id, name, type, forcesubscribe, timemodified FROM mdl_forum WHERE course=$COURSE_ID AND name LIKE '%Clinical Case Study Discussions%' ORDER BY id DESC LIMIT 1")

FORUM_FOUND="false"
FORUM_ID=""
FORUM_NAME=""
FORUM_TYPE=""
FORUM_SUBSCRIBE=""
FORUM_TIMEMODIFIED="0"

if [ -n "$FORUM_DATA" ]; then
    FORUM_FOUND="true"
    FORUM_ID=$(echo "$FORUM_DATA" | cut -f1 | tr -d '[:space:]')
    FORUM_NAME=$(echo "$FORUM_DATA" | cut -f2)
    FORUM_TYPE=$(echo "$FORUM_DATA" | cut -f3)
    FORUM_SUBSCRIBE=$(echo "$FORUM_DATA" | cut -f4 | tr -d '[:space:]')
    FORUM_TIMEMODIFIED=$(echo "$FORUM_DATA" | cut -f5 | tr -d '[:space:]')
    
    echo "Forum found: ID=$FORUM_ID, Name='$FORUM_NAME', Type='$FORUM_TYPE', Subscribe=$FORUM_SUBSCRIBE"
else
    echo "Forum 'Clinical Case Study Discussions' NOT found in BIO101"
fi

# Check for discussion topic if forum was found
DISCUSSION_FOUND="false"
DISCUSSION_SUBJECT=""
DISCUSSION_MESSAGE=""
DISCUSSION_TIMECREATED="0"

if [ "$FORUM_FOUND" = "true" ]; then
    # Look for discussion in this forum
    # Join with mdl_forum_posts to get the message of the first post (parent=0)
    # Note: mdl_forum_discussions links to mdl_forum. mdl_forum_posts links to discussion.
    
    # First find the discussion record
    DISC_DATA=$(moodle_query "SELECT id, name, timecreated FROM mdl_forum_discussions WHERE forum=$FORUM_ID AND name LIKE '%Cellular Respiration Disorder%' ORDER BY id DESC LIMIT 1")
    
    if [ -n "$DISC_DATA" ]; then
        DISCUSSION_FOUND="true"
        DISC_ID=$(echo "$DISC_DATA" | cut -f1 | tr -d '[:space:]')
        DISCUSSION_SUBJECT=$(echo "$DISC_DATA" | cut -f2)
        DISCUSSION_TIMECREATED=$(echo "$DISC_DATA" | cut -f3 | tr -d '[:space:]')
        
        # Now get the post content (message) for this discussion
        # We look for the post with parent=0 (the initial post)
        POST_MESSAGE=$(moodle_query "SELECT message FROM mdl_forum_posts WHERE discussion=$DISC_ID AND parent=0 LIMIT 1")
        DISCUSSION_MESSAGE="$POST_MESSAGE"
        
        echo "Discussion found: ID=$DISC_ID, Subject='$DISCUSSION_SUBJECT'"
    else
        echo "Discussion topic 'Cellular Respiration Disorder' NOT found in forum"
    fi
fi

# Escape strings for JSON
FORUM_NAME_ESC=$(echo "$FORUM_NAME" | sed 's/"/\\"/g')
DISCUSSION_SUBJECT_ESC=$(echo "$DISCUSSION_SUBJECT" | sed 's/"/\\"/g')
# Message can contain newlines/quotes, be careful. Using jq would be better but trying robust sed
DISCUSSION_MESSAGE_ESC=$(echo "$DISCUSSION_MESSAGE" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | tr -d '\n' | tr -d '\r')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/create_forum_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "course_id": ${COURSE_ID:-0},
    "initial_forum_count": ${INITIAL_FORUM_COUNT:-0},
    "current_forum_count": ${CURRENT_FORUM_COUNT:-0},
    "task_start_time": ${TASK_START_TIME:-0},
    "forum_found": $FORUM_FOUND,
    "forum": {
        "id": "${FORUM_ID}",
        "name": "${FORUM_NAME_ESC}",
        "type": "${FORUM_TYPE}",
        "forcesubscribe": "${FORUM_SUBSCRIBE}",
        "timemodified": ${FORUM_TIMEMODIFIED:-0}
    },
    "discussion_found": $DISCUSSION_FOUND,
    "discussion": {
        "subject": "${DISCUSSION_SUBJECT_ESC}",
        "message": "${DISCUSSION_MESSAGE_ESC}",
        "timecreated": ${DISCUSSION_TIMECREATED:-0}
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/create_forum_result.json

echo ""
cat /tmp/create_forum_result.json
echo ""
echo "=== Export Complete ==="