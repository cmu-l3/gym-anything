#!/bin/bash
echo "=== Exporting recover_and_purge_trash result ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Retrieve IDs tracked during setup
TARGET_ID=$(cat /tmp/target_id.txt 2>/dev/null || echo "0")
IFS=',' read -r JUNK1_ID JUNK2_ID JUNK3_ID < /tmp/junk_ids.txt 2>/dev/null || true

echo "Checking status for Target ID: $TARGET_ID"
echo "Checking status for Junk IDs: $JUNK1_ID, $JUNK2_ID, $JUNK3_ID"

# 1. Check Target Status
# We need to know if it exists (deleted_at IS NULL or NOT NULL) or is gone entirely
# status column: 1=Active, 2=Pending, 3=Closed, 9=Spam? 
# FreeScout uses SoftDeletes: deleted_at column determines if it's in Trash
TARGET_DATA=$(fs_query "SELECT id, status, deleted_at FROM conversations WHERE id=$TARGET_ID")

TARGET_EXISTS="false"
TARGET_IS_ACTIVE="false"
TARGET_IS_TRASHED="false"

if [ -n "$TARGET_DATA" ]; then
    TARGET_EXISTS="true"
    DELETED_AT=$(echo "$TARGET_DATA" | cut -f3)
    
    if [ "$DELETED_AT" == "NULL" ] || [ -z "$DELETED_AT" ]; then
        TARGET_IS_ACTIVE="true"
    else
        TARGET_IS_TRASHED="true"
    fi
fi

# 2. Check Junk Status
# They should be permanently deleted (row missing from DB)
JUNK_COUNT=0
if [ -n "$JUNK1_ID" ]; then
    EXISTS=$(fs_query "SELECT COUNT(*) FROM conversations WHERE id=$JUNK1_ID")
    JUNK_COUNT=$((JUNK_COUNT + EXISTS))
fi
if [ -n "$JUNK2_ID" ]; then
    EXISTS=$(fs_query "SELECT COUNT(*) FROM conversations WHERE id=$JUNK2_ID")
    JUNK_COUNT=$((JUNK_COUNT + EXISTS))
fi
if [ -n "$JUNK3_ID" ]; then
    EXISTS=$(fs_query "SELECT COUNT(*) FROM conversations WHERE id=$JUNK3_ID")
    JUNK_COUNT=$((JUNK_COUNT + EXISTS))
fi

# 3. Check if Trash is generally empty
# Count all conversations where deleted_at IS NOT NULL
REMAINING_TRASH_COUNT=$(fs_query "SELECT COUNT(*) FROM conversations WHERE deleted_at IS NOT NULL" 2>/dev/null || echo "0")

# Anti-gaming: Check timestamp of target update
# If it was restored, updated_at should be > task_start_time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TARGET_UPDATED_AT_TS=0
if [ "$TARGET_EXISTS" = "true" ]; then
    # Get unix timestamp of updated_at
    TARGET_UPDATED_AT=$(fs_query "SELECT UNIX_TIMESTAMP(updated_at) FROM conversations WHERE id=$TARGET_ID")
    TARGET_UPDATED_AT_TS=${TARGET_UPDATED_AT:-0}
fi

MODIFIED_DURING_TASK="false"
if [ "$TARGET_UPDATED_AT_TS" -gt "$TASK_START" ]; then
    MODIFIED_DURING_TASK="true"
fi

# Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_exists": $TARGET_EXISTS,
    "target_is_active": $TARGET_IS_ACTIVE,
    "target_is_trashed": $TARGET_IS_TRASHED,
    "junk_remaining_count": $JUNK_COUNT,
    "total_trash_count": $REMAINING_TRASH_COUNT,
    "target_modified_during_task": $MODIFIED_DURING_TASK,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result with permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="