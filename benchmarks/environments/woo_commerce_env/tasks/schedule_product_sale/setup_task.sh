#!/bin/bash
set -e
echo "=== Setting up schedule_product_sale task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Verify database connectivity
check_db_connection || { echo "FATAL: Cannot connect to database"; exit 1; }

# Verify the target product exists
PRODUCT_INFO=$(get_product_by_sku "WBH-001")
if [ -z "$PRODUCT_INFO" ]; then
    echo "FATAL: Product WBH-001 not found in database"
    exit 1
fi
PRODUCT_ID=$(echo "$PRODUCT_INFO" | awk '{print $1}')
echo "Target product ID: $PRODUCT_ID (Wireless Bluetooth Headphones)"

# Record product ID for export script
echo "$PRODUCT_ID" > /tmp/task_product_id.txt

# Clear any existing sale price/schedule to ensure clean state
# We delete the meta keys so the agent has to create them
wc_query "DELETE FROM wp_postmeta WHERE post_id=$PRODUCT_ID AND meta_key='_sale_price'"
wc_query "DELETE FROM wp_postmeta WHERE post_id=$PRODUCT_ID AND meta_key='_sale_price_dates_from'"
wc_query "DELETE FROM wp_postmeta WHERE post_id=$PRODUCT_ID AND meta_key='_sale_price_dates_to'"

# Re-insert empty sale price meta (standard WP state for no sale)
wc_query "INSERT INTO wp_postmeta (post_id, meta_key, meta_value) VALUES ($PRODUCT_ID, '_sale_price', '')"

# Ensure regular price is correct
wc_query "UPDATE wp_postmeta SET meta_value='79.99' WHERE post_id=$PRODUCT_ID AND meta_key='_regular_price'"
wc_query "UPDATE wp_postmeta SET meta_value='79.99' WHERE post_id=$PRODUCT_ID AND meta_key='_price'"

echo "Cleared existing sale schedule for product $PRODUCT_ID"

# Kill any existing Firefox
pkill -f firefox 2>/dev/null || true
sleep 2

# Launch Firefox to the Products list page
# Ensure WordPress is ready first
if ! ensure_wordpress_shown 60; then
    echo "FATAL: WordPress not reachable"
    exit 1
fi

PRODUCTS_URL="http://localhost/wp-admin/edit.php?post_type=product"
echo "Opening Firefox to: $PRODUCTS_URL"
su - ga -c "DISPLAY=:1 firefox --no-remote '$PRODUCTS_URL' &"

# Wait for Firefox window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i -E "firefox|mozilla|product"; then
        echo "Firefox window detected after ${i}s"
        break
    fi
    sleep 1
done
sleep 5

# Maximize Firefox
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="