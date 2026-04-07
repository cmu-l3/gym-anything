#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
COURSE_ID=$(cat /tmp/course_id.txt 2>/dev/null || echo "0")

# Take final screenshot showing end state
take_screenshot /tmp/task_final.png

# Initialize variables
FORUM_EXISTS="false"
FORUM_ID="0"
ASSESSED="0"
SCALE="0"
CREATED_DURING_TASK="false"

# 1. Fetch Forum Data
FORUM_DATA=$(moodle_query "SELECT id, assessed, scale, timemodified FROM mdl_forum WHERE course=$COURSE_ID AND name='Week 1 Discussion: The Tragedy of Hamlet' ORDER BY id DESC LIMIT 1")

if [ -n "$FORUM_DATA" ]; then
    FORUM_EXISTS="true"
    FORUM_ID=$(echo "$FORUM_DATA" | cut -f1)
    ASSESSED=$(echo "$FORUM_DATA" | cut -f2)
    SCALE=$(echo "$FORUM_DATA" | cut -f3)
    TIMEMODIFIED=$(echo "$FORUM_DATA" | cut -f4)

    if [ "$TIMEMODIFIED" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi
fi

# 2. Fetch Grade Item Data
GRADE_ITEM_EXISTS="false"
GRADE_MAX="0"
if [ "$FORUM_ID" != "0" ]; then
    GRADE_DATA=$(moodle_query "SELECT id, grademax FROM mdl_grade_items WHERE itemmodule='forum' AND iteminstance=$FORUM_ID LIMIT 1")
    if [ -n "$GRADE_DATA" ]; then
        GRADE_ITEM_EXISTS="true"
        GRADE_MAX=$(echo "$GRADE_DATA" | cut -f2)
    fi
fi

# 3. Fetch Discussion Thread
DISCUSSION_EXISTS="false"
DISCUSSION_ID="0"
if [ "$FORUM_ID" != "0" ]; then
    # Use wildcards to avoid SQL escaping issues with single quotes
    DISCUSSION_DATA=$(moodle_query "SELECT id FROM mdl_forum_discussions WHERE forum=$FORUM_ID AND name LIKE '%Analysis of Hamlet%Soliloquy%' LIMIT 1")
    if [ -n "$DISCUSSION_DATA" ]; then
        DISCUSSION_EXISTS="true"
        DISCUSSION_ID=$(echo "$DISCUSSION_DATA" | cut -f1)
    fi
fi

# 4. Fetch Post Content safely (base64 encode to prevent JSON breaks)
POST_EXISTS="false"
POST_CONTENT_B64=""
if [ "$DISCUSSION_ID" != "0" ]; then
    moodle_query "SELECT message FROM mdl_forum_posts WHERE discussion=$DISCUSSION_ID ORDER BY id ASC LIMIT 1" > /tmp/post_message.txt
    if [ -s /tmp/post_message.txt ]; then
        POST_EXISTS="true"
        POST_CONTENT_B64=$(base64 -w 0 /tmp/post_message.txt)
    fi
fi

# Build JSON payload
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "course_id": $COURSE_ID,
    "forum_exists": $FORUM_EXISTS,
    "forum_id": $FORUM_ID,
    "assessed": $ASSESSED,
    "scale": $SCALE,
    "created_during_task": $CREATED_DURING_TASK,
    "grade_item_exists": $GRADE_ITEM_EXISTS,
    "grade_max": "$GRADE_MAX",
    "discussion_exists": $DISCUSSION_EXISTS,
    "post_exists": $POST_EXISTS,
    "post_content_b64": "$POST_CONTENT_B64"
}
EOF

# Move payload safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
echo "=== Export complete ==="