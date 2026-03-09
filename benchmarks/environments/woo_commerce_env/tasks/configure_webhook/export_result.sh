#!/bin/bash
# Export script for Configure Webhook task

echo "=== Exporting Configure Webhook Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Verify database connectivity before proceeding
if ! check_db_connection; then
    echo '{"error": "database_unreachable", "webhook_found": false}' > /tmp/configure_webhook_result.json
    echo "=== Export Failed: Database Unreachable ==="
    exit 1
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Get task timings
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Get counts
INITIAL_COUNT=$(cat /tmp/initial_webhook_count.txt 2>/dev/null || echo "0")
CURRENT_COUNT=$(wc_query "SELECT COUNT(*) FROM wp_wc_webhooks" 2>/dev/null || echo "0")

echo "Webhook count: initial=$INITIAL_COUNT, current=$CURRENT_COUNT"

# Search for the webhook
# Strategy: Look for exact name match first, then fallback to newest created webhook
TARGET_NAME="Fulfillment Dispatch - New Orders"
echo "Searching for webhook with name: '$TARGET_NAME'"

# We fetch columns: webhook_id, status, name, topic, delivery_url, secret, date_created_gmt
# Note: date_created_gmt is in 'YYYY-MM-DD HH:MM:SS' format
WEBHOOK_DATA=$(wc_query "SELECT webhook_id, status, name, topic, delivery_url, secret, UNIX_TIMESTAMP(date_created_gmt)
    FROM wp_wc_webhooks
    WHERE name = '$TARGET_NAME'
    LIMIT 1" 2>/dev/null)

SEARCH_METHOD="exact_name"

if [ -z "$WEBHOOK_DATA" ]; then
    echo "Exact name match not found. checking for newest webhook created after task start..."
    # Fallback: Get the most recent webhook created after task start
    # We add a small buffer (5 seconds) to task start time just in case of clock skew,
    # but strictly it should be > TASK_START
    WEBHOOK_DATA=$(wc_query "SELECT webhook_id, status, name, topic, delivery_url, secret, UNIX_TIMESTAMP(date_created_gmt)
        FROM wp_wc_webhooks
        WHERE UNIX_TIMESTAMP(date_created_gmt) >= $TASK_START
        ORDER BY webhook_id DESC
        LIMIT 1" 2>/dev/null)
    
    if [ -n "$WEBHOOK_DATA" ]; then
        SEARCH_METHOD="newest_created"
        echo "Found a new webhook created during task."
    else
        SEARCH_METHOD="not_found"
        echo "No relevant webhook found."
    fi
fi

# Parse Data
WEBHOOK_FOUND="false"
WH_ID=""
WH_STATUS=""
WH_NAME=""
WH_TOPIC=""
WH_URL=""
WH_SECRET=""
WH_CREATED_TS="0"

if [ -n "$WEBHOOK_DATA" ]; then
    WEBHOOK_FOUND="true"
    WH_ID=$(echo "$WEBHOOK_DATA" | cut -f1)
    WH_STATUS=$(echo "$WEBHOOK_DATA" | cut -f2)
    WH_NAME=$(echo "$WEBHOOK_DATA" | cut -f3)
    WH_TOPIC=$(echo "$WEBHOOK_DATA" | cut -f4)
    WH_URL=$(echo "$WEBHOOK_DATA" | cut -f5)
    WH_SECRET=$(echo "$WEBHOOK_DATA" | cut -f6)
    WH_CREATED_TS=$(echo "$WEBHOOK_DATA" | cut -f7)
    
    echo "Webhook Details Found:"
    echo "  ID: $WH_ID"
    echo "  Name: $WH_NAME"
    echo "  Status: $WH_STATUS"
    echo "  Topic: $WH_TOPIC"
    echo "  URL: $WH_URL"
    echo "  Secret: $WH_SECRET"
    echo "  Created TS: $WH_CREATED_TS (Task Start: $TASK_START)"
fi

# JSON Escaping
WH_NAME_ESC=$(json_escape "$WH_NAME")
WH_TOPIC_ESC=$(json_escape "$WH_TOPIC")
WH_URL_ESC=$(json_escape "$WH_URL")
WH_SECRET_ESC=$(json_escape "$WH_SECRET")

# Create result JSON
TEMP_JSON=$(mktemp /tmp/configure_webhook_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_count": ${INITIAL_COUNT:-0},
    "current_count": ${CURRENT_COUNT:-0},
    "webhook_found": $WEBHOOK_FOUND,
    "search_method": "$SEARCH_METHOD",
    "webhook": {
        "id": "$WH_ID",
        "status": "$WH_STATUS",
        "name": "$WH_NAME_ESC",
        "topic": "$WH_TOPIC_ESC",
        "delivery_url": "$WH_URL_ESC",
        "secret": "$WH_SECRET_ESC",
        "created_timestamp": ${WH_CREATED_TS:-0}
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/configure_webhook_result.json

echo ""
cat /tmp/configure_webhook_result.json
echo ""
echo "=== Export Complete ==="