#!/bin/bash
echo "=== Exporting Sequential Pipeline Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Export Channel Configuration (Static Analysis)
# We need to find the specific channel to check the waitForPrevious setting
CHANNEL_ID=$(get_channel_id "Registration_Pipeline")
CHANNEL_JSON="{}"

if [ -n "$CHANNEL_ID" ]; then
    echo "Found Channel ID: $CHANNEL_ID"
    # Fetch full JSON config using the API
    CHANNEL_JSON=$(curl -sk -u admin:admin \
        -H "X-Requested-With: OpenAPI" \
        -H "Accept: application/json" \
        "https://localhost:8443/api/channels/$CHANNEL_ID" 2>/dev/null)
else
    echo "Channel 'Registration_Pipeline' not found."
fi

# 2. Check Database State (Count)
DB_COUNT=$(query_postgres "SELECT COUNT(*) FROM billing_log;" 2>/dev/null || echo "0")

# 3. Check File State (Count)
FILE_COUNT=$(ls -1 /tmp/billing_out/ 2>/dev/null | wc -l)

# 4. Check if Channel is Started
CHANNEL_STATE="UNKNOWN"
if [ -n "$CHANNEL_ID" ]; then
    CHANNEL_STATE=$(get_channel_status_api "$CHANNEL_ID")
fi

# 5. Compile Result JSON
# We include the full channel config so the verifier can check 'waitForPrevious'
cat > /tmp/export_data.json << EOF
{
    "channel_found": $([ -n "$CHANNEL_ID" ] && echo "true" || echo "false"),
    "channel_id": "$CHANNEL_ID",
    "channel_state": "$CHANNEL_STATE",
    "db_row_count": $DB_COUNT,
    "file_count": $FILE_COUNT,
    "channel_config": $CHANNEL_JSON,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to standard result location with permissions
write_result_json "/tmp/task_result.json" "$(cat /tmp/export_data.json)"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="