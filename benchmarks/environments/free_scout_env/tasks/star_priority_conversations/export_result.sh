#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting star_priority_conversations result ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Retrieve saved state
MAILBOX_ID=$(cat /tmp/task_mailbox_id.txt 2>/dev/null || echo "1")
INITIAL_STARRED=$(cat /tmp/initial_starred_count.txt 2>/dev/null || echo "0")
INITIAL_STARRED=$(echo "$INITIAL_STARRED" | tr -cd '0-9')
[ -z "$INITIAL_STARRED" ] && INITIAL_STARRED=0

# Navigate to Starred view to capture evidence
# This ensures the VLM can see the final state clearly
echo "Navigating to Starred folder for evidence..."
focus_firefox
navigate_to_url "http://localhost:8080/mailbox/${MAILBOX_ID}/folder/starred"
sleep 5
take_screenshot /tmp/task_final.png

# ===== Find starred conversations via database =====

# Find the Starred folder ID for user 1 (admin)
# FreeScout uses folder type 25 for Starred
STARRED_FOLDER_IDS=$(fs_query "SELECT GROUP_CONCAT(id) FROM folders WHERE user_id = 1 AND type = 25" 2>/dev/null || echo "")

# Fallback: search by name if type lookup fails
if [ -z "$STARRED_FOLDER_IDS" ] || [ "$STARRED_FOLDER_IDS" = "NULL" ]; then
    STARRED_FOLDER_IDS=$(fs_query "SELECT GROUP_CONCAT(id) FROM folders WHERE user_id = 1 AND LOWER(name) LIKE '%star%'" 2>/dev/null || echo "")
fi

echo "Starred folder IDs: $STARRED_FOLDER_IDS"

# Get starred conversation details
STARRED_COUNT=0
STARRED_SUBJECTS=""
STARRED_CONV_IDS=""

if [ -n "$STARRED_FOLDER_IDS" ] && [ "$STARRED_FOLDER_IDS" != "NULL" ]; then
    # Get count
    STARRED_COUNT=$(fs_query "SELECT COUNT(DISTINCT cf.conversation_id) FROM conversation_folder cf WHERE cf.folder_id IN ($STARRED_FOLDER_IDS)" 2>/dev/null || echo "0")
    STARRED_COUNT=$(echo "$STARRED_COUNT" | tr -cd '0-9')
    [ -z "$STARRED_COUNT" ] && STARRED_COUNT=0
    
    # Get subjects (concatenated with pipe separator for parsing)
    # Using JSON_ARRAYAGG would be cleaner but requires newer MariaDB/MySQL, so we use string concat
    # We'll export raw list and let Python parse carefully
    STARRED_SUBJECTS=$(fs_query "SELECT c.subject FROM conversations c JOIN conversation_folder cf ON c.id = cf.conversation_id WHERE cf.folder_id IN ($STARRED_FOLDER_IDS) ORDER BY c.id ASC" 2>/dev/null || echo "")
    
    # Get IDs
    STARRED_CONV_IDS=$(fs_query "SELECT GROUP_CONCAT(DISTINCT cf.conversation_id) FROM conversation_folder cf WHERE cf.folder_id IN ($STARRED_FOLDER_IDS)" 2>/dev/null || echo "")
fi

echo "Final starred count: $STARRED_COUNT"
echo "Starred IDs: $STARRED_CONV_IDS"

# Helper to safely dump multi-line string to JSON
escape_json_string() {
    python3 -c "import json, sys; print(json.dumps(sys.stdin.read().strip()))"
}

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_starred_count": $INITIAL_STARRED,
    "final_starred_count": $STARRED_COUNT,
    "starred_folder_ids": "$STARRED_FOLDER_IDS",
    "starred_subjects_raw": $(echo "$STARRED_SUBJECTS" | escape_json_string),
    "starred_conv_ids": "$STARRED_CONV_IDS",
    "mailbox_id": "$MAILBOX_ID",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save result to standard location
safe_write_result "$TEMP_JSON" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="