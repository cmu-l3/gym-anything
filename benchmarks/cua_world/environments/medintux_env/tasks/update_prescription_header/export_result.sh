#!/bin/bash
echo "=== Exporting update_prescription_header results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Get template path recorded during setup
TEMPLATE_PATH=$(cat /tmp/template_path.txt 2>/dev/null)
INITIAL_MTIME=$(cat /tmp/initial_file_mtime.txt 2>/dev/null || echo "0")

echo "Checking file: $TEMPLATE_PATH"

# Initialize result variables
FILE_EXISTS="false"
FILE_MODIFIED="false"
CONTENT_MATCH_ADDRESS="false"
CONTENT_MATCH_CITY="false"
CONTENT_MATCH_PHONE="false"
CONTENT_REMOVED_OLD="false"
FILE_SIZE="0"
FILE_CONTENT_B64=""

if [ -f "$TEMPLATE_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$TEMPLATE_PATH")
    CURRENT_MTIME=$(stat -c %Y "$TEMPLATE_PATH")

    # Check modification time (Anti-gaming)
    # We add a small buffer (1s) to avoid race conditions with fast scripts
    if [ "$CURRENT_MTIME" -gt "$INITIAL_MTIME" ]; then
        FILE_MODIFIED="true"
    fi

    # Read content for analysis
    # Convert to UTF-8 just in case MedinTux saved as ISO-8859-1
    CONTENT=$(cat "$TEMPLATE_PATH" | iconv -f ISO-8859-1 -t UTF-8 2>/dev/null || cat "$TEMPLATE_PATH")
    
    # Check for new strings
    if echo "$CONTENT" | grep -q "50 Avenue de la Nouvelle Santé"; then
        CONTENT_MATCH_ADDRESS="true"
    fi
    if echo "$CONTENT" | grep -q "75000 Paris"; then
        CONTENT_MATCH_CITY="true"
    fi
    if echo "$CONTENT" | grep -q "01 23 45 67 89"; then
        CONTENT_MATCH_PHONE="true"
    fi

    # Check for absence of old strings
    if ! echo "$CONTENT" | grep -q "Rue de l'Ancienne Poste"; then
        CONTENT_REMOVED_OLD="true"
    fi
    
    # Store base64 content for python verifier (optional, usually grep above is enough but good for debug)
    FILE_CONTENT_B64=$(base64 -w 0 "$TEMPLATE_PATH")
fi

# Check if DrTux or Manager is running
APP_RUNNING=$(pgrep -f "DrTux.exe" > /dev/null || pgrep -f "Manager.exe" > /dev/null && echo "true" || echo "false")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "file_size": $FILE_SIZE,
    "content_match_address": $CONTENT_MATCH_ADDRESS,
    "content_match_city": $CONTENT_MATCH_CITY,
    "content_match_phone": $CONTENT_MATCH_PHONE,
    "content_removed_old": $CONTENT_REMOVED_OLD,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="