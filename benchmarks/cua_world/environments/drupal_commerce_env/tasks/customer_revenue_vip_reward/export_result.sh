#!/bin/bash
# Export script for customer_revenue_vip_reward task
echo "=== Exporting customer_revenue_vip_reward Result ==="

. /workspace/scripts/task_utils.sh

if ! type drupal_db_query &>/dev/null; then
    drupal_db_query() {
        docker exec drupal-mariadb mysql -u drupal -pdrupalpass drupal -N -e "$1" 2>/dev/null
    }
    take_screenshot() {
        local path="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 scrot "$path" 2>/dev/null || DISPLAY=:1 import -window root "$path" 2>/dev/null || true
    }
fi

take_screenshot /tmp/task_end_screenshot.png

DRUPAL_DIR="/var/www/html/drupal"
DRUSH="$DRUPAL_DIR/vendor/bin/drush"

# Clear caches
cd "$DRUPAL_DIR" && $DRUSH cr 2>/dev/null || true

# Read baselines
INITIAL_PROMO_COUNT=$(cat /tmp/initial_promo_count 2>/dev/null || echo "0")
INITIAL_COUPON_COUNT=$(cat /tmp/initial_coupon_count 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# ===== 1. VIEW =====
VIEW_EXISTS="false"
VIEW_NAME=""

# Try common machine names first
for name in customer_revenue customer-revenue customer_revenue_report; do
    if $DRUSH config:get "views.view.$name" > /dev/null 2>&1; then
        VIEW_EXISTS="true"
        VIEW_NAME="$name"
        $DRUSH config:get "views.view.$name" --format=json > /tmp/view_config.json 2>/dev/null
        break
    fi
done

# Fallback: search router for the expected path
if [ "$VIEW_EXISTS" = "false" ]; then
    ROUTE_NAME=$(drupal_db_query "SELECT name FROM router WHERE path = '/admin/commerce/customer-revenue' LIMIT 1" | tr -d '[:space:]')
    if [ -n "$ROUTE_NAME" ]; then
        EXTRACTED=$(echo "$ROUTE_NAME" | sed -n 's/^view\.\([^.]*\)\..*/\1/p')
        if [ -n "$EXTRACTED" ] && $DRUSH config:get "views.view.$EXTRACTED" > /dev/null 2>&1; then
            VIEW_EXISTS="true"
            VIEW_NAME="$EXTRACTED"
            $DRUSH config:get "views.view.$EXTRACTED" --format=json > /tmp/view_config.json 2>/dev/null
        fi
    fi
fi

PATH_REGISTERED="false"
PATH_CHECK=$(drupal_db_query "SELECT COUNT(*) FROM router WHERE path LIKE '%customer-revenue%' OR path LIKE '%customer_revenue%'" 2>/dev/null || echo "0")
if [ "$PATH_CHECK" -gt 0 ] 2>/dev/null; then
    PATH_REGISTERED="true"
fi

# ===== 2. PROMOTION =====
# Search for VIP Reward promotion in DB (same pattern as configure_seasonal_promotion)
PROMO_DATA=$(drupal_db_query "SELECT promotion_id, name, offer__target_plugin_id, status, require_coupon FROM commerce_promotion_field_data WHERE name LIKE '%VIP%Reward%' OR name LIKE '%vip%reward%' ORDER BY promotion_id DESC LIMIT 1")

PROMO_FOUND="false"
PROMO_ID=""
PROMO_NAME=""
PROMO_OFFER_TYPE=""
PROMO_STATUS=""
PROMO_REQUIRE_COUPON=""

if [ -n "$PROMO_DATA" ]; then
    PROMO_FOUND="true"
    PROMO_ID=$(echo "$PROMO_DATA" | cut -f1)
    PROMO_NAME=$(echo "$PROMO_DATA" | cut -f2)
    PROMO_OFFER_TYPE=$(echo "$PROMO_DATA" | cut -f3)
    PROMO_STATUS=$(echo "$PROMO_DATA" | cut -f4)
    PROMO_REQUIRE_COUPON=$(echo "$PROMO_DATA" | cut -f5)
fi

# Extract offer percentage from serialized PHP config blob
OFFER_PERCENTAGE=""
if [ -n "$PROMO_ID" ]; then
    OFFER_PERCENTAGE=$(drupal_db_query "SELECT CAST(offer__target_plugin_configuration AS CHAR) FROM commerce_promotion_field_data WHERE promotion_id=$PROMO_ID" | python3 -c "
import sys, re
data = sys.stdin.read()
m = re.search(r'\"percentage\";s:\d+:\"([0-9.]+)\"', data)
if m:
    print(m.group(1))
else:
    m2 = re.search(r'percentage.*?([0-9.]+)', data)
    if m2:
        print(m2.group(1))
    else:
        print('')
" 2>/dev/null)
fi

# Check for VIP coupon
COUPON_DATA=$(drupal_db_query "SELECT id, code, usage_limit, status FROM commerce_promotion_coupon WHERE UPPER(code) LIKE 'VIP-%' ORDER BY id DESC LIMIT 1")

COUPON_FOUND="false"
COUPON_CODE=""
COUPON_USAGE_LIMIT=""
COUPON_STATUS=""
COUPON_ID=""

if [ -n "$COUPON_DATA" ]; then
    COUPON_FOUND="true"
    COUPON_ID=$(echo "$COUPON_DATA" | cut -f1)
    COUPON_CODE=$(echo "$COUPON_DATA" | cut -f2)
    COUPON_USAGE_LIMIT=$(echo "$COUPON_DATA" | cut -f3)
    COUPON_STATUS=$(echo "$COUPON_DATA" | cut -f4)
fi

# Check if coupon is linked to VIP promotion
COUPON_LINKED="false"
if [ -n "$PROMO_ID" ] && [ -n "$COUPON_ID" ]; then
    LINK_CHECK=$(drupal_db_query "SELECT COUNT(*) FROM commerce_promotion__coupons WHERE entity_id=$PROMO_ID AND coupons_target_id=$COUPON_ID")
    if [ "$LINK_CHECK" -gt 0 ] 2>/dev/null; then
        COUPON_LINKED="true"
    fi
fi

# Check for minimum order condition
HAS_MIN_ORDER="false"
MIN_ORDER_AMOUNT=""
if [ -n "$PROMO_ID" ]; then
    CONDITION_DATA=$(drupal_db_query "SELECT conditions__target_plugin_configuration FROM commerce_promotion__conditions WHERE entity_id=$PROMO_ID AND conditions__target_plugin_id LIKE '%total_price%' LIMIT 1" 2>/dev/null)
    if [ -n "$CONDITION_DATA" ]; then
        HAS_MIN_ORDER="true"
        MIN_ORDER_AMOUNT=$(echo "$CONDITION_DATA" | python3 -c "
import sys, re
data = sys.stdin.read()
m = re.search(r'\"number\";s:\d+:\"([0-9.]+)\"', data)
if m:
    print(m.group(1))
else:
    m2 = re.search(r'number.*?([0-9.]+)', data)
    if m2:
        print(m2.group(1))
    else:
        print('')
" 2>/dev/null)
    fi
fi

# Check store assignment
STORE_ASSIGNED="false"
if [ -n "$PROMO_ID" ]; then
    STORE_CHECK=$(drupal_db_query "SELECT COUNT(*) FROM commerce_promotion__stores WHERE entity_id=$PROMO_ID AND stores_target_id=1")
    if [ "$STORE_CHECK" -gt 0 ] 2>/dev/null; then
        STORE_ASSIGNED="true"
    fi
fi

# ===== 3. MENU LINK =====
MENU_LINK_EXISTS="false"
MENU_LINK_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM menu_link_content_data WHERE title LIKE '%Customer Revenue%' AND menu_name='main'" 2>/dev/null || echo "0")
if [ "$MENU_LINK_COUNT" -gt 0 ] 2>/dev/null; then
    MENU_LINK_EXISTS="true"
fi

# Current counts
CURRENT_PROMO_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM commerce_promotion_field_data")
CURRENT_PROMO_COUNT=${CURRENT_PROMO_COUNT:-0}
CURRENT_COUPON_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM commerce_promotion_coupon")
CURRENT_COUPON_COUNT=${CURRENT_COUPON_COUNT:-0}

# ===== WRITE RESULT =====
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $(date +%s),
    "view_exists": $VIEW_EXISTS,
    "view_name": "$(echo "$VIEW_NAME" | tr -d '\n\r')",
    "path_registered": $PATH_REGISTERED,
    "config_file_path": "/tmp/view_config.json",
    "promo_found": $PROMO_FOUND,
    "promo_id": ${PROMO_ID:-null},
    "promo_name": "$(echo "$PROMO_NAME" | tr -d '\n\r')",
    "promo_offer_type": "$(echo "$PROMO_OFFER_TYPE" | tr -d '\n\r')",
    "promo_status": ${PROMO_STATUS:-0},
    "promo_require_coupon": ${PROMO_REQUIRE_COUPON:-0},
    "offer_percentage": "${OFFER_PERCENTAGE:-}",
    "coupon_found": $COUPON_FOUND,
    "coupon_code": "$(echo "$COUPON_CODE" | tr -d '\n\r')",
    "coupon_usage_limit": ${COUPON_USAGE_LIMIT:-0},
    "coupon_linked": $COUPON_LINKED,
    "has_min_order": $HAS_MIN_ORDER,
    "min_order_amount": "${MIN_ORDER_AMOUNT:-}",
    "store_assigned": $STORE_ASSIGNED,
    "menu_link_exists": $MENU_LINK_EXISTS,
    "initial_promo_count": $INITIAL_PROMO_COUNT,
    "current_promo_count": $CURRENT_PROMO_COUNT,
    "initial_coupon_count": $INITIAL_COUPON_COUNT,
    "current_coupon_count": $CURRENT_COUPON_COUNT
}
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
if [ -f /tmp/view_config.json ]; then
    chmod 666 /tmp/view_config.json 2>/dev/null || true
fi

echo "Result JSON:"
cat /tmp/task_result.json
echo "=== Export Complete ==="
