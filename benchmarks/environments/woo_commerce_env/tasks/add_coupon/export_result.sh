#!/bin/bash
# Export script for Add Coupon task

echo "=== Exporting Add Coupon Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Verify database connectivity before proceeding
if ! check_db_connection; then
    echo '{"error": "database_unreachable", "coupon_found": false, "coupon": {}}' > /tmp/add_coupon_result.json
    echo "=== Export Failed: Database Unreachable ==="
    exit 1
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Get current coupon count
CURRENT_COUNT=$(get_coupon_count 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_coupon_count 2>/dev/null || echo "0")

echo "Coupon count: initial=$INITIAL_COUNT, current=$CURRENT_COUNT"

# Debug: Show most recent coupons
echo ""
echo "=== DEBUG: Most recent coupons in database ==="
wc_query_headers "SELECT ID, post_title, post_status
    FROM wp_posts
    WHERE post_type = 'shop_coupon'
    ORDER BY ID DESC LIMIT 5" 2>/dev/null
echo "=== END DEBUG ==="
echo ""

# Check for the target coupon using case-insensitive matching
echo "Checking for coupon code 'SUMMER25' (case-insensitive)..."
COUPON_DATA=$(get_coupon_by_code "SUMMER25" 2>/dev/null)

# If not found by exact code, try partial match
if [ -z "$COUPON_DATA" ]; then
    echo "Exact code match not found, trying partial match..."
    COUPON_DATA=$(wc_query "SELECT ID, post_title, post_status
        FROM wp_posts
        WHERE post_type = 'shop_coupon'
        AND LOWER(post_title) LIKE '%summer25%'
        ORDER BY ID DESC LIMIT 1" 2>/dev/null)
fi

# NOTE: No "newest entity" fallback - if the specific coupon is not found,
# it's reported as not found. The verifier handles this appropriately.

# Parse coupon data
COUPON_FOUND="false"
COUPON_ID=""
COUPON_CODE=""
COUPON_STATUS=""
COUPON_DISCOUNT_TYPE=""
COUPON_AMOUNT=""
COUPON_USAGE_LIMIT=""
COUPON_MINIMUM_AMOUNT=""

if [ -n "$COUPON_DATA" ]; then
    COUPON_FOUND="true"
    COUPON_ID=$(echo "$COUPON_DATA" | cut -f1)
    COUPON_CODE=$(echo "$COUPON_DATA" | cut -f2)
    COUPON_STATUS=$(echo "$COUPON_DATA" | cut -f3)

    # Get coupon metadata
    COUPON_DISCOUNT_TYPE=$(get_coupon_discount_type "$COUPON_ID" 2>/dev/null)
    COUPON_AMOUNT=$(get_coupon_amount "$COUPON_ID" 2>/dev/null)
    COUPON_USAGE_LIMIT=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$COUPON_ID AND meta_key='usage_limit' LIMIT 1" 2>/dev/null)
    COUPON_MINIMUM_AMOUNT=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$COUPON_ID AND meta_key='minimum_amount' LIMIT 1" 2>/dev/null)

    echo "Coupon found: ID=$COUPON_ID, Code='$COUPON_CODE', Type='$COUPON_DISCOUNT_TYPE', Amount='$COUPON_AMOUNT', UsageLimit='$COUPON_USAGE_LIMIT', MinAmount='$COUPON_MINIMUM_AMOUNT'"
else
    echo "Coupon 'SUMMER25' NOT found in database"
fi

# Escape special characters for JSON (handles quotes, backslashes, newlines, etc.)
COUPON_CODE_ESC=$(json_escape "$COUPON_CODE")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/add_coupon_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_coupon_count": ${INITIAL_COUNT:-0},
    "current_coupon_count": ${CURRENT_COUNT:-0},
    "coupon_found": $COUPON_FOUND,
    "coupon": {
        "id": "$COUPON_ID",
        "code": "$COUPON_CODE_ESC",
        "status": "$COUPON_STATUS",
        "discount_type": "$COUPON_DISCOUNT_TYPE",
        "amount": "$COUPON_AMOUNT",
        "usage_limit": "$COUPON_USAGE_LIMIT",
        "minimum_amount": "$COUPON_MINIMUM_AMOUNT"
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/add_coupon_result.json

echo ""
cat /tmp/add_coupon_result.json
echo ""
echo "=== Export Complete ==="
