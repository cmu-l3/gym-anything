#!/bin/bash
set -e
echo "=== Exporting configure_predictive_dialer result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query current database state
echo "Querying database..."

# Helper to run safe select
query_val() {
    docker exec vicidial mysql -ucron -p1234 -D asterisk -N -s -e \
    "SELECT $1 FROM vicidial_campaigns WHERE campaign_id='SALESOUT'" 2>/dev/null || echo ""
}

# Fetch all relevant fields
DIAL_METHOD=$(query_val "dial_method")
AUTO_DIAL_LEVEL=$(query_val "auto_dial_level")
HOPPER_LEVEL=$(query_val "hopper_level")
DIAL_TIMEOUT=$(query_val "dial_timeout")
CAMPAIGN_REC=$(query_val "campaign_rec")
DROP_CALL_SECONDS=$(query_val "drop_call_seconds")
CAMPAIGN_CID=$(query_val "campaign_cid")
CAMPAIGN_ACTIVE=$(query_val "active")

# Check if campaign still exists
if [ -z "$DIAL_METHOD" ]; then
    CAMPAIGN_EXISTS="false"
else
    CAMPAIGN_EXISTS="true"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "campaign_exists": $CAMPAIGN_EXISTS,
    "current_state": {
        "dial_method": "$DIAL_METHOD",
        "auto_dial_level": "$AUTO_DIAL_LEVEL",
        "hopper_level": "$HOPPER_LEVEL",
        "dial_timeout": "$DIAL_TIMEOUT",
        "campaign_rec": "$CAMPAIGN_REC",
        "drop_call_seconds": "$DROP_CALL_SECONDS",
        "campaign_cid": "$CAMPAIGN_CID",
        "active": "$CAMPAIGN_ACTIVE"
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with permissive permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="