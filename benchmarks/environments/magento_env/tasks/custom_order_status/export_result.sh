#!/bin/bash
# Export script for Custom Order Status task

echo "=== Exporting Custom Order Status Result ==="

source /workspace/scripts/task_utils.sh
take_screenshot /tmp/task_end_screenshot.png

# Get initial counts
INITIAL_STATUS_COUNT=$(cat /tmp/initial_status_count 2>/dev/null || echo "0")
INITIAL_STATE_COUNT=$(cat /tmp/initial_state_count 2>/dev/null || echo "0")

# Get current counts
CURRENT_STATUS_COUNT=$(magento_query "SELECT COUNT(*) FROM sales_order_status" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")
CURRENT_STATE_COUNT=$(magento_query "SELECT COUNT(*) FROM sales_order_status_state" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")

echo "Counts - Status: $INITIAL_STATUS_COUNT -> $CURRENT_STATUS_COUNT | State: $INITIAL_STATE_COUNT -> $CURRENT_STATE_COUNT"

# Helper to get status details as JSON object
get_status_json() {
    local code="$1"
    
    # Check if status exists
    local label=$(magento_query "SELECT label FROM sales_order_status WHERE status='$code'" 2>/dev/null | tail -1)
    
    # Check state assignment
    local state_data=$(magento_query "SELECT state, is_default, visible_on_front FROM sales_order_status_state WHERE status='$code'" 2>/dev/null | tail -1)
    local state=$(echo "$state_data" | awk -F'\t' '{print $1}')
    local is_default=$(echo "$state_data" | awk -F'\t' '{print $2}')
    local visible=$(echo "$state_data" | awk -F'\t' '{print $3}')
    
    local exists="false"
    if [ -n "$label" ]; then exists="true"; fi
    
    # Sanitize label for JSON
    local label_esc=$(echo "$label" | sed 's/"/\\"/g')
    
    echo "{"
    echo "  \"code\": \"$code\","
    echo "  \"exists\": $exists,"
    echo "  \"label\": \"$label_esc\","
    echo "  \"assigned_state\": \"$state\","
    echo "  \"is_default\": \"$is_default\","
    echo "  \"visible_on_front\": \"$visible\""
    echo "}"
}

# Collect data for the three expected statuses
JSON_QUALITY=$(get_status_json "quality_check")
JSON_PICKUP=$(get_status_json "ready_pickup")
JSON_SUPPLIER=$(get_status_json "supplier_delay")

# Create final JSON
TEMP_JSON=$(mktemp /tmp/order_status_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_status_count": ${INITIAL_STATUS_COUNT:-0},
    "current_status_count": ${CURRENT_STATUS_COUNT:-0},
    "initial_state_count": ${INITIAL_STATE_COUNT:-0},
    "current_state_count": ${CURRENT_STATE_COUNT:-0},
    "statuses": {
        "quality_check": $JSON_QUALITY,
        "ready_pickup": $JSON_PICKUP,
        "supplier_delay": $JSON_SUPPLIER
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/order_status_result.json

echo ""
cat /tmp/order_status_result.json
echo ""
echo "=== Export Complete ==="