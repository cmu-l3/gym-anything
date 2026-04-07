#!/bin/bash
# Export script for Generate Embedded Widget Code task

echo "=== Exporting Widget Code Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Get timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

OUTPUT_FILE="/home/ga/intranet_widget_code.html"
FILE_EXISTS="false"
FILE_CONTENT=""
FILE_SIZE="0"
FILE_MODIFIED_TIME="0"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    FILE_MODIFIED_TIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    # Read content (limit size to avoid huge JSONs)
    FILE_CONTENT=$(cat "$OUTPUT_FILE" | head -c 2000)
fi

# Attempt to retrieve Admin token from DB for verification
# Note: Matomo stores tokens in various places depending on version.
# We'll try to look it up to help the verifier, but verifier will also rely on regex.
# In newer Matomo, tokens are hashed, so we might only find the session token or 
# have to rely on the fact that the UI generated it.
# We will query the user table just in case.
ADMIN_TOKEN_HASH=$(matomo_query "SELECT token_auth FROM matomo_user WHERE login='admin'" 2>/dev/null || echo "")

# Escape content for JSON
escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\n/\\n/g; s/\r/\\r/g'
}

CONTENT_ESC=$(escape_json "$FILE_CONTENT")

# Create result JSON
TEMP_JSON=$(mktemp /tmp/widget_code_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_path": "$OUTPUT_FILE",
    "file_size": $FILE_SIZE,
    "file_modified_time": $FILE_MODIFIED_TIME,
    "file_content": "$CONTENT_ESC",
    "db_admin_token_hash": "$ADMIN_TOKEN_HASH",
    "screenshot_path": "/tmp/task_final_screenshot.png"
}
EOF

# Save result
rm -f /tmp/widget_code_result.json 2>/dev/null || sudo rm -f /tmp/widget_code_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/widget_code_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/widget_code_result.json
chmod 666 /tmp/widget_code_result.json 2>/dev/null || sudo chmod 666 /tmp/widget_code_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/widget_code_result.json"
echo "=== Export Complete ==="