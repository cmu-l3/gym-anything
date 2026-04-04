#!/bin/bash
# Export script for Create Coupon task
# Queries the Drupal database for verification data and saves to JSON

echo "=== Exporting Create Coupon Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Get initial counts recorded by setup_task.sh
INITIAL_PROMO_COUNT=$(cat /tmp/initial_promotion_count 2>/dev/null || echo "0")
INITIAL_COUPON_COUNT=$(cat /tmp/initial_coupon_count 2>/dev/null || echo "0")

# Get current counts
CURRENT_PROMO_COUNT=$(get_promotion_count 2>/dev/null || echo "0")
CURRENT_COUPON_COUNT=$(get_coupon_count 2>/dev/null || echo "0")

echo "Promotion count: initial=$INITIAL_PROMO_COUNT, current=$CURRENT_PROMO_COUNT"
echo "Coupon count: initial=$INITIAL_COUPON_COUNT, current=$CURRENT_COUPON_COUNT"

# Look for the expected promotion by name (case-insensitive)
EXPECTED_NAME="Summer Sale 20% Off"
echo "Checking for promotion '$EXPECTED_NAME'..."

PROMO_DATA=$(drupal_db_query "SELECT promotion_id, name, status FROM commerce_promotion_field_data WHERE LOWER(TRIM(name)) = LOWER(TRIM('$EXPECTED_NAME')) ORDER BY promotion_id DESC LIMIT 1" 2>/dev/null)

PROMO_FOUND="false"
PROMO_ID=""
PROMO_NAME=""
PROMO_STATUS=""

if [ -n "$PROMO_DATA" ] && [ "$PROMO_DATA" != "" ]; then
    PROMO_FOUND="true"
    PROMO_ID=$(echo "$PROMO_DATA" | awk '{print $1}')
    PROMO_NAME=$(drupal_db_query "SELECT name FROM commerce_promotion_field_data WHERE promotion_id = $PROMO_ID LIMIT 1" 2>/dev/null)
    PROMO_STATUS_RAW=$(drupal_db_query "SELECT status FROM commerce_promotion_field_data WHERE promotion_id = $PROMO_ID LIMIT 1" 2>/dev/null)
    if [ "$PROMO_STATUS_RAW" = "1" ]; then
        PROMO_STATUS="active"
    else
        PROMO_STATUS="disabled"
    fi
    echo "Promotion found: ID=$PROMO_ID, Name='$PROMO_NAME', Status=$PROMO_STATUS"
else
    echo "Promotion '$EXPECTED_NAME' NOT found by exact name"
    # Try partial match
    PROMO_DATA=$(drupal_db_query "SELECT promotion_id, name FROM commerce_promotion_field_data WHERE LOWER(name) LIKE '%summer%' ORDER BY promotion_id DESC LIMIT 1" 2>/dev/null)
    if [ -n "$PROMO_DATA" ]; then
        PROMO_FOUND="true"
        PROMO_ID=$(echo "$PROMO_DATA" | awk '{print $1}')
        PROMO_NAME=$(drupal_db_query "SELECT name FROM commerce_promotion_field_data WHERE promotion_id = $PROMO_ID LIMIT 1" 2>/dev/null)
        PROMO_STATUS_RAW=$(drupal_db_query "SELECT status FROM commerce_promotion_field_data WHERE promotion_id = $PROMO_ID LIMIT 1" 2>/dev/null)
        if [ "$PROMO_STATUS_RAW" = "1" ]; then
            PROMO_STATUS="active"
        else
            PROMO_STATUS="disabled"
        fi
        echo "Promotion found by partial match: ID=$PROMO_ID, Name='$PROMO_NAME'"
    fi
fi

# Check for the expected coupon code
EXPECTED_COUPON="SUMMER20"
echo "Checking for coupon code '$EXPECTED_COUPON'..."

COUPON_FOUND="false"
COUPON_CODE=""
COUPON_STATUS=""

if coupon_exists_by_code "$EXPECTED_COUPON" 2>/dev/null; then
    COUPON_FOUND="true"
    COUPON_CODE="$EXPECTED_COUPON"
    COUPON_STATUS="active"
    echo "Coupon code '$EXPECTED_COUPON' found and active"
else
    # Check if coupon exists but is disabled
    COUPON_CHECK=$(drupal_db_query "SELECT code, status FROM commerce_promotion_coupon WHERE LOWER(TRIM(code)) = LOWER(TRIM('$EXPECTED_COUPON')) LIMIT 1" 2>/dev/null)
    if [ -n "$COUPON_CHECK" ]; then
        COUPON_FOUND="true"
        COUPON_CODE="$EXPECTED_COUPON"
        COUPON_STATUS="disabled"
        echo "Coupon code '$EXPECTED_COUPON' found but disabled"
    else
        echo "Coupon code '$EXPECTED_COUPON' NOT found"
    fi
fi

# Try to get the offer type from the promotion config
OFFER_TYPE=""
OFFER_AMOUNT=""
if [ -n "$PROMO_ID" ] && [ "$PROMO_ID" != "" ]; then
    # Drupal Commerce stores offer configuration in serialized format in the config table
    # We can check the promotion's offer plugin ID
    OFFER_TYPE=$(drupal_db_query "SELECT offer__target_plugin_id FROM commerce_promotion_field_data WHERE promotion_id = $PROMO_ID LIMIT 1" 2>/dev/null)
    OFFER_AMOUNT=$(drupal_db_query "SELECT offer__target_plugin_configuration FROM commerce_promotion_field_data WHERE promotion_id = $PROMO_ID LIMIT 1" 2>/dev/null)
    echo "Offer type: $OFFER_TYPE"
fi

# Determine if it's a percentage type
IS_PERCENTAGE="false"
if echo "$OFFER_TYPE" | grep -qi "percentage"; then
    IS_PERCENTAGE="true"
fi

# Build result JSON
create_result_json /tmp/task_result.json \
    "initial_promotion_count=$INITIAL_PROMO_COUNT" \
    "current_promotion_count=$CURRENT_PROMO_COUNT" \
    "initial_coupon_count=$INITIAL_COUPON_COUNT" \
    "current_coupon_count=$CURRENT_COUPON_COUNT" \
    "promotion_found=$PROMO_FOUND" \
    "promotion_id=$PROMO_ID" \
    "promotion_name=$(json_escape "$PROMO_NAME")" \
    "promotion_status=$(json_escape "$PROMO_STATUS")" \
    "coupon_found=$COUPON_FOUND" \
    "coupon_code=$(json_escape "$COUPON_CODE")" \
    "coupon_status=$(json_escape "$COUPON_STATUS")" \
    "offer_type=$(json_escape "$OFFER_TYPE")" \
    "is_percentage=$IS_PERCENTAGE"

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo ""
echo "Result JSON:"
cat /tmp/task_result.json

echo ""
echo "=== Export Complete ==="
