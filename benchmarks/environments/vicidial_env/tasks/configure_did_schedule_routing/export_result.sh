#!/bin/bash
set -e

echo "=== Exporting Configure DID Schedule Routing Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query the DID configuration
echo "Querying DID configuration..."
DID_JSON=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e \
    "SELECT did_pattern, call_time_id, filter_action, filter_extension, filter_clean_cid_number FROM vicidial_inbound_dids WHERE did_pattern='8885559999';" | \
    while read -r pattern calltime action ext clean; do
        # Create a simple JSON object string
        echo "{\"did_pattern\": \"$pattern\", \"call_time_id\": \"$calltime\", \"filter_action\": \"$action\", \"filter_extension\": \"$ext\", \"filter_clean_cid_number\": \"$clean\"}"
    done
)

# If query failed or returned empty
if [ -z "$DID_JSON" ]; then
    DID_JSON="null"
fi

# Check if application was running
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "did_config": $DID_JSON,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="