#!/bin/bash
echo "=== Exporting merge_duplicate_customers result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Load setup info
TARGET_ID="0"
SOURCE_ID="0"
TARGET_EMAIL=""
SOURCE_EMAIL=""

if [ -f /tmp/merge_setup_info.json ]; then
    TARGET_ID=$(jq -r .target_id /tmp/merge_setup_info.json)
    SOURCE_ID=$(jq -r .source_id /tmp/merge_setup_info.json)
    TARGET_EMAIL=$(jq -r .target_email /tmp/merge_setup_info.json)
    SOURCE_EMAIL=$(jq -r .source_email /tmp/merge_setup_info.json)
fi

echo "Checking status of Target ID: $TARGET_ID and Source ID: $SOURCE_ID"

# Check if Target profile still exists
TARGET_EXISTS=$(fs_query "SELECT COUNT(*) FROM customers WHERE id = $TARGET_ID")
TARGET_FIRST_NAME=$(fs_query "SELECT first_name FROM customers WHERE id = $TARGET_ID" 2>/dev/null || echo "")

# Check if Source profile still exists (Should be 0 if merged/deleted)
SOURCE_EXISTS=$(fs_query "SELECT COUNT(*) FROM customers WHERE id = $SOURCE_ID")

# Get all emails associated with the Target ID
# We expect BOTH emails to be here now
TARGET_EMAILS=$(fs_query "SELECT email FROM emails WHERE customer_id = $TARGET_ID")

# Check global customer count
INITIAL_COUNT=$(cat /tmp/initial_customer_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(get_customer_count)

# Check timestamp of target update
TARGET_UPDATED_AT=$(fs_query "SELECT updated_at FROM customers WHERE id = $TARGET_ID")
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Determine if update happened during task
UPDATED_DURING_TASK="false"
if [ -n "$TARGET_UPDATED_AT" ]; then
    UPDATED_TS=$(date -d "$TARGET_UPDATED_AT" +%s 2>/dev/null || echo "0")
    if [ "$UPDATED_TS" -gt "$TASK_START" ]; then
        UPDATED_DURING_TASK="true"
    fi
fi

# Check conversation migration (optional but good verification)
# Did the conversation from the source customer move to the target customer?
SOURCE_CONV_MOVED="false"
# We find conversations owned by target that have the source email address in conversation fields
# OR strictly check that conversation count for target increased by 1 (assuming we made 1 for each)
TARGET_CONV_COUNT=$(fs_query "SELECT COUNT(*) FROM conversations WHERE customer_id = $TARGET_ID")

# Construct JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
jq -n \
    --arg target_id "$TARGET_ID" \
    --arg source_id "$SOURCE_ID" \
    --arg target_exists "$TARGET_EXISTS" \
    --arg source_exists "$SOURCE_EXISTS" \
    --arg target_emails "$TARGET_EMAILS" \
    --arg expected_source_email "$SOURCE_EMAIL" \
    --arg expected_target_email "$TARGET_EMAIL" \
    --arg initial_count "$INITIAL_COUNT" \
    --arg current_count "$CURRENT_COUNT" \
    --arg updated_during_task "$UPDATED_DURING_TASK" \
    --arg target_conv_count "$TARGET_CONV_COUNT" \
    '{
        target_id: $target_id,
        source_id: $source_id,
        target_profile_exists: ($target_exists == "1"),
        source_profile_exists: ($source_exists == "1"),
        target_associated_emails: $target_emails,
        expected_source_email_merged: ($target_emails | contains($expected_source_email)),
        expected_target_email_present: ($target_emails | contains($expected_target_email)),
        customer_count_reduced: ($current_count | tonumber < ($initial_count | tonumber)),
        count_diff: (($initial_count | tonumber) - ($current_count | tonumber)),
        target_updated_during_task: ($updated_during_task == "true"),
        target_conversation_count: ($target_conv_count | tonumber)
    }' > "$TEMP_JSON"

safe_write_result "$TEMP_JSON" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="