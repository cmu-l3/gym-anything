#!/bin/bash
# Export script for Update Order Status task

echo "=== Exporting Update Order Status Result ==="

source /workspace/scripts/task_utils.sh

# Verify database
if ! check_db_connection; then
    echo '{"error": "database_unreachable"}' > /tmp/task_result.json
    exit 1
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Read context
TARGET_ORDER_ID=$(cat /tmp/target_order_id.txt 2>/dev/null)
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TRACKING_NUMBER="TRACK-2024-78542"

echo "Checking Order ID: $TARGET_ORDER_ID"

# 1. Get Final Order Status
ORDER_STATUS=$(wc_query "SELECT post_status FROM wp_posts WHERE ID=$TARGET_ORDER_ID LIMIT 1" 2>/dev/null)
echo "Final Order Status: $ORDER_STATUS"

# 2. Check for the specific note
# Look for a comment on this order containing the tracking number
NOTE_QUERY="SELECT comment_ID, comment_content, comment_date_gmt 
            FROM wp_comments 
            WHERE comment_post_ID=$TARGET_ORDER_ID 
            AND comment_type='order_note' 
            AND comment_content LIKE '%$TRACKING_NUMBER%' 
            ORDER BY comment_ID DESC LIMIT 1"

NOTE_DATA=$(wc_query "$NOTE_QUERY" 2>/dev/null)

NOTE_FOUND="false"
NOTE_CONTENT=""
NOTE_DATE_GMT=""
NOTE_IS_CUSTOMER="false"

if [ -n "$NOTE_DATA" ]; then
    NOTE_FOUND="true"
    NOTE_ID=$(echo "$NOTE_DATA" | cut -f1)
    NOTE_CONTENT=$(echo "$NOTE_DATA" | cut -f2)
    NOTE_DATE_GMT=$(echo "$NOTE_DATA" | cut -f3)
    
    # Check if it is a customer note (metadata 'is_customer_note')
    # In WooCommerce, is_customer_note=1 means sent to customer. 0 means private.
    IS_CUST_VAL=$(wc_query "SELECT meta_value FROM wp_commentmeta WHERE comment_id=$NOTE_ID AND meta_key='is_customer_note' LIMIT 1" 2>/dev/null)
    
    if [ "$IS_CUST_VAL" == "1" ]; then
        NOTE_IS_CUSTOMER="true"
    else
        NOTE_IS_CUSTOMER="false"
    fi
fi

# 3. Check Order Modification Time
ORDER_MODIFIED_GMT=$(wc_query "SELECT post_modified_gmt FROM wp_posts WHERE ID=$TARGET_ORDER_ID LIMIT 1" 2>/dev/null)

# Escape for JSON
NOTE_CONTENT_ESC=$(json_escape "$NOTE_CONTENT")

# Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_order_id": "$TARGET_ORDER_ID",
    "final_status": "$ORDER_STATUS",
    "note_found": $NOTE_FOUND,
    "note_content": "$NOTE_CONTENT_ESC",
    "note_is_customer_note": $NOTE_IS_CUSTOMER,
    "timestamps": {
        "task_start": $TASK_START_TIME,
        "note_date_gmt": "$NOTE_DATE_GMT",
        "order_modified_gmt": "$ORDER_MODIFIED_GMT"
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
safe_write_json "$TEMP_JSON" /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="