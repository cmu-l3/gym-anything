#!/bin/bash
echo "=== Exporting search_flag_security_incident result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Load Target ID
TARGET_CONV_ID=$(cat /tmp/target_conv_id.txt | cut -d'=' -f2)

# 1. Check for "Security Alert" tag creation
TAG_ID=$(fs_query "SELECT id FROM tags WHERE name = 'Security Alert' LIMIT 1" 2>/dev/null)
TAG_EXISTS="false"
if [ -n "$TAG_ID" ]; then
    TAG_EXISTS="true"
fi

# 2. Check if Target is Tagged
TARGET_TAGGED="false"
if [ "$TAG_EXISTS" = "true" ]; then
    IS_TAGGED=$(fs_query "SELECT conversation_id FROM conversation_tag WHERE conversation_id = $TARGET_CONV_ID AND tag_id = $TAG_ID" 2>/dev/null)
    if [ -n "$IS_TAGGED" ]; then
        TARGET_TAGGED="true"
    fi
fi

# 3. Check Target Assignee
TARGET_USER_ID=$(fs_query "SELECT user_id FROM conversations WHERE id = $TARGET_CONV_ID" 2>/dev/null)
ADMIN_USER_ID=$(fs_query "SELECT id FROM users WHERE email = 'admin@helpdesk.local'" 2>/dev/null)
IS_ASSIGNED_TO_ADMIN="false"

if [ "$TARGET_USER_ID" = "$ADMIN_USER_ID" ]; then
    IS_ASSIGNED_TO_ADMIN="true"
fi

# 4. Check for Internal Note
# Type 2 is NOTE
NOTE_FOUND="false"
NOTE_CONTENT=""
NOTES_DATA=$(fs_query "SELECT body FROM threads WHERE conversation_id = $TARGET_CONV_ID AND type = 2" 2>/dev/null)

if [ -n "$NOTES_DATA" ]; then
    # Check if any note contains "header analysis"
    if echo "$NOTES_DATA" | grep -qi "header analysis"; then
        NOTE_FOUND="true"
        NOTE_CONTENT=$(echo "$NOTES_DATA" | grep -i "header analysis" | head -1)
    fi
fi

# 5. Check Distractors (Anti-Gaming)
DISTRACTORS_TAGGED_COUNT=0
DISTRACTOR_IDS=$(cat /tmp/distractor_ids.txt 2>/dev/null || echo "")

if [ "$TAG_EXISTS" = "true" ] && [ -n "$DISTRACTOR_IDS" ]; then
    for DID in $DISTRACTOR_IDS; do
        IS_D_TAGGED=$(fs_query "SELECT conversation_id FROM conversation_tag WHERE conversation_id = $DID AND tag_id = $TAG_ID" 2>/dev/null)
        if [ -n "$IS_D_TAGGED" ]; then
            DISTRACTORS_TAGGED_COUNT=$((DISTRACTORS_TAGGED_COUNT + 1))
        fi
    done
fi

# Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "tag_exists": $TAG_EXISTS,
    "target_tagged": $TARGET_TAGGED,
    "assigned_to_admin": $IS_ASSIGNED_TO_ADMIN,
    "note_found": $NOTE_FOUND,
    "distractors_tagged_count": $DISTRACTORS_TAGGED_COUNT,
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="