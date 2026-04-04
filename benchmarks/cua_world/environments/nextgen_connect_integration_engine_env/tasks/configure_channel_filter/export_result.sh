#!/bin/bash
echo "=== Exporting configure_channel_filter task result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Get initial and current channel counts
INITIAL=$(cat /tmp/initial_filter_channel_count 2>/dev/null || echo "0")
CURRENT=$(get_channel_count)

echo "Initial channel count: $INITIAL"
echo "Current channel count: $CURRENT"

# Check for filter channel in database
FILTER_CHANNEL_EXISTS="false"
CHANNEL_ID=""
CHANNEL_NAME=""
HAS_FILTER="false"
CHANNEL_STATUS="unknown"
LISTEN_PORT=""

# Query for channels with "filter" or "adt" in the name
FILTER_QUERY="SELECT id, name FROM channel WHERE LOWER(name) LIKE '%filter%' OR LOWER(name) LIKE '%adt%';"
FILTER_DATA=$(query_postgres "$FILTER_QUERY" 2>/dev/null || true)

if [ -n "$FILTER_DATA" ]; then
    FILTER_CHANNEL_EXISTS="true"
    CHANNEL_ID=$(echo "$FILTER_DATA" | head -1 | cut -d'|' -f1)
    CHANNEL_NAME=$(echo "$FILTER_DATA" | head -1 | cut -d'|' -f2)
    echo "Found filter channel: $CHANNEL_NAME (ID: $CHANNEL_ID)"

    # Check channel XML config for actual filter rules (not just empty <filter> tags)
    CHANNEL_XML=$(query_postgres "SELECT channel FROM channel WHERE id='$CHANNEL_ID';" 2>/dev/null || true)
    # Look for filter elements with content: JavaScript rules, Rule elements, MSH-9/ADT references
    if echo "$CHANNEL_XML" | grep -qi "com.mirth.connect.plugins.rulebuilder\|RuleBuilderRule\|javascript.*adt\|MSH.*9\|messageType\|msg\[.*MSH\|Rule.*element"; then
        HAS_FILTER="true"
        echo "Filter logic detected in channel configuration"
    fi

    # Extract listening port from channel XML
    LISTEN_PORT=$(echo "$CHANNEL_XML" | python3 -c "
import sys, re
xml = sys.stdin.read()
m = re.search(r'<port>(\d+)</port>', xml)
if m: print(m.group(1))
else: print('')
" 2>/dev/null || true)
fi

# If exact match not found, check for any new channel
if [ "$FILTER_CHANNEL_EXISTS" = "false" ] && [ "$CURRENT" -gt "$INITIAL" ]; then
    LATEST_DATA=$(query_postgres "SELECT id, name FROM channel ORDER BY revision DESC LIMIT 1;" 2>/dev/null || true)
    if [ -n "$LATEST_DATA" ]; then
        FILTER_CHANNEL_EXISTS="true"
        CHANNEL_ID=$(echo "$LATEST_DATA" | head -1 | cut -d'|' -f1)
        CHANNEL_NAME=$(echo "$LATEST_DATA" | head -1 | cut -d'|' -f2)
        echo "Found latest channel: $CHANNEL_NAME (ID: $CHANNEL_ID)"

        # Check for actual filter rules in the latest channel
        CHANNEL_XML=$(query_postgres "SELECT channel FROM channel WHERE id='$CHANNEL_ID';" 2>/dev/null || true)
        if echo "$CHANNEL_XML" | grep -qi "com.mirth.connect.plugins.rulebuilder\|RuleBuilderRule\|javascript.*adt\|MSH.*9\|messageType\|msg\[.*MSH\|Rule.*element"; then
            HAS_FILTER="true"
        fi

        LISTEN_PORT=$(echo "$CHANNEL_XML" | python3 -c "
import sys, re
xml = sys.stdin.read()
m = re.search(r'<port>(\d+)</port>', xml)
if m: print(m.group(1))
else: print('')
" 2>/dev/null || true)
    fi
fi

# Check deployment status
if [ -n "$CHANNEL_ID" ]; then
    DEPLOYED_CHECK=$(query_postgres "SELECT COUNT(*) FROM d_channels WHERE channel_id='$CHANNEL_ID';" 2>/dev/null || echo "0")
    if [ "$DEPLOYED_CHECK" -gt 0 ] 2>/dev/null; then
        CHANNEL_STATUS="deployed"
    fi
    API_STATUS=$(get_channel_status_api "$CHANNEL_ID" 2>/dev/null || echo "UNKNOWN")
    if [ "$API_STATUS" != "UNKNOWN" ] && [ -n "$API_STATUS" ]; then
        CHANNEL_STATUS="$API_STATUS"
    fi
fi

echo "Listen port: $LISTEN_PORT, Filter detected: $HAS_FILTER, Status: $CHANNEL_STATUS"

# Create JSON result
JSON_CONTENT=$(cat <<EOF
{
    "initial_count": $INITIAL,
    "current_count": $CURRENT,
    "filter_channel_exists": $FILTER_CHANNEL_EXISTS,
    "channel_id": "$CHANNEL_ID",
    "channel_name": "$CHANNEL_NAME",
    "has_filter": $HAS_FILTER,
    "channel_status": "$CHANNEL_STATUS",
    "listen_port": "$LISTEN_PORT",
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "/tmp/configure_channel_filter_result.json" "$JSON_CONTENT"

echo "Result saved to /tmp/configure_channel_filter_result.json"
cat /tmp/configure_channel_filter_result.json
echo "=== Export complete ==="
