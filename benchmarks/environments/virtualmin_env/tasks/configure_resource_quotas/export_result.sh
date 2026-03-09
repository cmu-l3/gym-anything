#!/bin/bash
echo "=== Exporting task results: configure_resource_quotas ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Collect configuration for each domain
DOMAINS=("acmecorp.test" "greenleaf.test" "craftworks.test")
RESULTS_JSON_PART=""

for i in "${!DOMAINS[@]}"; do
    domain="${DOMAINS[$i]}"
    
    # Get raw multiline output
    RAW_CONFIG=$(virtualmin list-domains --domain "$domain" --multiline 2>/dev/null)
    
    # Extract specific values using grep/sed
    # "Server byte quota: 2 GB" or "Server byte quota: 2147483648"
    DISK_QUOTA_RAW=$(echo "$RAW_CONFIG" | grep -i "Server byte quota" | head -1 | awk -F': ' '{print $2}')
    
    # "Bandwidth limit: 10 GB" or similar
    BW_LIMIT_RAW=$(echo "$RAW_CONFIG" | grep -i "Bandwidth limit" | head -1 | awk -F': ' '{print $2}')
    
    # Check if modified from initial
    INITIAL_CONFIG=$(cat "/tmp/initial_state_${domain}.txt" 2>/dev/null)
    if [ "$RAW_CONFIG" != "$INITIAL_CONFIG" ]; then
        MODIFIED="true"
    else
        MODIFIED="false"
    fi

    # Construct JSON object for this domain
    # Use python to safely escape strings
    DOMAIN_JSON=$(python3 -c "import json; print(json.dumps({
        'domain': '$domain',
        'disk_quota_raw': '$DISK_QUOTA_RAW',
        'bandwidth_limit_raw': '$BW_LIMIT_RAW',
        'modified': $MODIFIED
    }))")
    
    if [ "$i" -gt 0 ]; then
        RESULTS_JSON_PART="$RESULTS_JSON_PART, $DOMAIN_JSON"
    else
        RESULTS_JSON_PART="$DOMAIN_JSON"
    fi
done

# Check if Firefox is still running
APP_RUNNING="false"
if firefox_is_running; then
    APP_RUNNING="true"
fi

# Create final JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "domains": [$RESULTS_JSON_PART],
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="