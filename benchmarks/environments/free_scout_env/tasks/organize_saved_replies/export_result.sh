#!/bin/bash
echo "=== Exporting organize_saved_replies result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Load IDs
MAILBOX_ID=$(cat /tmp/task_mailbox_id.txt 2>/dev/null || echo "1")
REPLY_ID=$(cat /tmp/task_reply_id.txt 2>/dev/null || echo "0")
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Checking state for Mailbox: $MAILBOX_ID, Reply: $REPLY_ID"

# We use PHP via docker exec to get a clean JSON object of the state
# This avoids parsing complex SQL outputs in bash
# We need to escape the PHP code for the bash string
PHP_CODE="
\$m_id = $MAILBOX_ID;
\$r_id = $REPLY_ID;

// Check category
\$cat = \\App\\SavedReplyCategory::where('mailbox_id', \$m_id)->where('name', 'Billing')->first();

// Check reply
\$reply = \\App\\SavedReply::find(\$r_id);

\$result = [
    'category_exists' => !!\$cat,
    'category_id' => \$cat ? \$cat->id : null,
    'reply_exists' => !!\$reply,
    'reply_name' => \$reply ? \$reply->name : '',
    'reply_category_id' => \$reply ? \$reply->category_id : null,
    'reply_updated_at' => \$reply ? \$reply->updated_at->timestamp : 0,
    'task_start_time' => $TASK_START_TIME
];

echo 'JSON_RESULT:' . json_encode(\$result);
"

# Run the query
OUTPUT=$(fs_tinker "$PHP_CODE")

# Extract JSON
JSON_STRING=$(echo "$OUTPUT" | grep 'JSON_RESULT:' | sed 's/JSON_RESULT://')

if [ -z "$JSON_STRING" ]; then
    echo "Error: Could not retrieve state from FreeScout"
    JSON_STRING="{}"
fi

# Write to temp file first
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
echo "$JSON_STRING" > "$TEMP_JSON"

# Move to final location
safe_write_result "$TEMP_JSON" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="