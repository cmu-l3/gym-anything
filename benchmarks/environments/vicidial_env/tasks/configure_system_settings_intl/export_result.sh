#!/bin/bash
set -e

echo "=== Exporting Task Result ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Query current database state
echo "Querying System Settings..."
DB_RESULT=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -B -e "SELECT use_non_latin, custom_fields_enabled, allow_chats, callback_limit, enable_queuemetrics_logging, allow_emails FROM system_settings LIMIT 1")

# Parse result into variables
# Output format is tab-separated: 1	1	1	1	1	1
read -r USE_NON_LATIN CUSTOM_FIELDS ALLOW_CHATS CALLBACK_LIMIT QUEUEMETRICS ALLOW_EMAILS <<< "$DB_RESULT"

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "final_values": {
        "use_non_latin": "${USE_NON_LATIN:-0}",
        "custom_fields_enabled": "${CUSTOM_FIELDS:-0}",
        "allow_chats": "${ALLOW_CHATS:-0}",
        "callback_limit": "${CALLBACK_LIMIT:-0}",
        "enable_queuemetrics_logging": "${QUEUEMETRICS:-0}",
        "allow_emails": "${ALLOW_EMAILS:-0}"
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Safely copy to standard location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="