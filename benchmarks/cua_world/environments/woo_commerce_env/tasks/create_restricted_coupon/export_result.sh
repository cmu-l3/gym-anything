#!/bin/bash
echo "=== Exporting Create Restricted Coupon Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Get Task Start Time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TARGET_CAT_ID=$(cat /tmp/target_category_id.txt 2>/dev/null)

# 3. Search for the coupon using WP-CLI
# We use WP-CLI because parsing serialized metadata for categories from SQL is painful in bash
echo "Searching for coupon 'CLOTHING-DEAL'..."

# Fetch coupon data as JSON
# We look for exact code match logic in Python, here we just fetch what we find
COUPON_JSON=$(wp wc coupon list --search="CLOTHING-DEAL" --format=json --user=admin --allow-root 2>/dev/null | jq -r '.[0] // empty')

COUPON_FOUND="false"
COUPON_DETAILS="{}"

if [ -n "$COUPON_JSON" ]; then
    COUPON_FOUND="true"
    COUPON_DETAILS="$COUPON_JSON"
    echo "Coupon found."
else
    echo "Coupon 'CLOTHING-DEAL' NOT found."
fi

# 4. Get Category Name map (for debugging/verification if ID matches)
# We know the ID from setup, but let's confirm what the agent used
# (The verifier will check if the coupon's category list contains TARGET_CAT_ID)

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "target_category_id": ${TARGET_CAT_ID:-0},
    "coupon_found": $COUPON_FOUND,
    "coupon_data": $COUPON_DETAILS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"