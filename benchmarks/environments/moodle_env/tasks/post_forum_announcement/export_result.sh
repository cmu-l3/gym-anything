#!/bin/bash
# Export script for Post Forum Announcement task

echo "=== Exporting Forum Announcement Result ==="

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

# Get BIO101 course ID
COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='BIO101'" | tr -d '[:space:]')

# Get announcements forum ID
FORUM_ID=$(cat /tmp/announcements_forum_id 2>/dev/null || echo "0")
if [ "$FORUM_ID" = "0" ] || [ -z "$FORUM_ID" ]; then
    FORUM_ID=$(moodle_query "SELECT id FROM mdl_forum WHERE course=$COURSE_ID AND type='news' LIMIT 1" | tr -d '[:space:]')
fi

# Get baseline
INITIAL_DISCUSSION_COUNT=$(cat /tmp/initial_discussion_count 2>/dev/null || echo "0")

# Current discussion count
CURRENT_DISCUSSION_COUNT="0"
if [ -n "$FORUM_ID" ] && [ "$FORUM_ID" != "0" ]; then
    CURRENT_DISCUSSION_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_forum_discussions WHERE forum=$FORUM_ID" | tr -d '[:space:]')
fi
CURRENT_DISCUSSION_COUNT=${CURRENT_DISCUSSION_COUNT:-0}

echo "Discussion count: initial=$INITIAL_DISCUSSION_COUNT, current=$CURRENT_DISCUSSION_COUNT"

# Find the most recent discussion (potential new post)
POST_FOUND="false"
POST_SUBJECT=""
POST_MESSAGE=""
POST_USERID=""
POST_FORUM_COURSE=""
DISCUSSION_NAME=""

if [ -n "$FORUM_ID" ] && [ "$FORUM_ID" != "0" ]; then
    # Get newest discussion in the announcements forum
    DISC_DATA=$(moodle_query "SELECT d.id, d.name, d.course FROM mdl_forum_discussions d WHERE d.forum=$FORUM_ID ORDER BY d.id DESC LIMIT 1")

    if [ -n "$DISC_DATA" ]; then
        DISC_ID=$(echo "$DISC_DATA" | cut -f1 | tr -d '[:space:]')
        DISCUSSION_NAME=$(echo "$DISC_DATA" | cut -f2)
        POST_FORUM_COURSE=$(echo "$DISC_DATA" | cut -f3 | tr -d '[:space:]')

        # Get the first post (parent=0) of this discussion
        POST_DATA=$(moodle_query "SELECT p.subject, p.message, p.userid FROM mdl_forum_posts p WHERE p.discussion=$DISC_ID AND p.parent=0 LIMIT 1")

        if [ -n "$POST_DATA" ]; then
            POST_FOUND="true"
            POST_SUBJECT=$(echo "$POST_DATA" | cut -f1)
            POST_MESSAGE=$(echo "$POST_DATA" | cut -f2)
            POST_USERID=$(echo "$POST_DATA" | cut -f3 | tr -d '[:space:]')

            echo "Found post: Subject='$POST_SUBJECT', UserID=$POST_USERID"
        fi
    fi
fi

# Check content keywords in the message
HAS_BIO101="false"
HAS_CELL_BIOLOGY="false"
HAS_SYLLABUS="false"
MSG_LOWER=$(echo "$POST_MESSAGE" | tr '[:upper:]' '[:lower:]')
echo "$MSG_LOWER" | grep -qi "bio101\|bio 101\|biology" && HAS_BIO101="true"
echo "$MSG_LOWER" | grep -qi "cell biology" && HAS_CELL_BIOLOGY="true"
echo "$MSG_LOWER" | grep -qi "syllabus" && HAS_SYLLABUS="true"

# Escape for JSON
POST_SUBJECT_ESC=$(echo "$POST_SUBJECT" | sed 's/"/\\"/g' | tr '\n' ' ')
POST_MESSAGE_SHORT=$(echo "$POST_MESSAGE" | head -c 500 | sed 's/"/\\"/g' | tr '\n' ' ')
DISCUSSION_NAME_ESC=$(echo "$DISCUSSION_NAME" | sed 's/"/\\"/g' | tr '\n' ' ')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/forum_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "course_id": ${COURSE_ID:-0},
    "forum_id": ${FORUM_ID:-0},
    "initial_discussion_count": ${INITIAL_DISCUSSION_COUNT:-0},
    "current_discussion_count": ${CURRENT_DISCUSSION_COUNT:-0},
    "post_found": $POST_FOUND,
    "post_subject": "$POST_SUBJECT_ESC",
    "post_message_preview": "$POST_MESSAGE_SHORT",
    "post_userid": "$POST_USERID",
    "post_forum_course": "$POST_FORUM_COURSE",
    "discussion_name": "$DISCUSSION_NAME_ESC",
    "has_bio101_mention": $HAS_BIO101,
    "has_cell_biology_mention": $HAS_CELL_BIOLOGY,
    "has_syllabus_mention": $HAS_SYLLABUS,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/post_forum_announcement_result.json

echo ""
cat /tmp/post_forum_announcement_result.json
echo ""
echo "=== Export Complete ==="
