#!/bin/bash
set -e
echo "=== Exporting Configure Product Settings Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Retrieve current values from database
# We use wc_query to get raw values directly from wp_options
echo "Querying final settings..."

get_option() {
    wc_query "SELECT option_value FROM wp_options WHERE option_name='$1' LIMIT 1"
}

VAL_REDIRECT=$(get_option "woocommerce_cart_redirect_after_add")
VAL_AJAX=$(get_option "woocommerce_enable_ajax_add_to_cart")
VAL_WEIGHT=$(get_option "woocommerce_weight_unit")
VAL_DIMENSION=$(get_option "woocommerce_dimension_unit")
VAL_REVIEWS=$(get_option "woocommerce_enable_reviews")
VAL_VERIFIED_LABEL=$(get_option "woocommerce_review_rating_verification_label")
VAL_VERIFIED_REQ=$(get_option "woocommerce_review_rating_verification_required")
VAL_RATING=$(get_option "woocommerce_enable_review_rating")
VAL_RATING_REQ=$(get_option "woocommerce_review_rating_required")

# Check if application was running
APP_RUNNING="false"
if pgrep -f "firefox" > /dev/null; then
    APP_RUNNING="true"
fi

# Create JSON result
# Using python to create safe JSON to avoid escaping issues with shell
python3 -c "
import json
import os

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'app_was_running': $APP_RUNNING == 1,
    'settings': {
        'woocommerce_cart_redirect_after_add': '$VAL_REDIRECT',
        'woocommerce_enable_ajax_add_to_cart': '$VAL_AJAX',
        'woocommerce_weight_unit': '$VAL_WEIGHT',
        'woocommerce_dimension_unit': '$VAL_DIMENSION',
        'woocommerce_enable_reviews': '$VAL_REVIEWS',
        'woocommerce_review_rating_verification_label': '$VAL_VERIFIED_LABEL',
        'woocommerce_review_rating_verification_required': '$VAL_VERIFIED_REQ',
        'woocommerce_enable_review_rating': '$VAL_RATING',
        'woocommerce_review_rating_required': '$VAL_RATING_REQ'
    },
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=4)
"

# Move to final location with permission handling
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="