#!/bin/bash
set -e
echo "=== Setting up Configure International Settings Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for database
for i in {1..30}; do
    if check_db_connection; then
        break
    fi
    sleep 2
done

echo "Resetting store to default US/USD state..."

# We use WP-CLI for reliable option setting (handles serialization/cache)
# Run as the web user or root with --allow-root, inside the WP directory

CD_CMD="cd /var/www/html/wordpress"
WP_CMD="wp --allow-root"

# 1. Reset Selling Locations to "All Countries"
$CD_CMD && $WP_CMD option update woocommerce_allowed_countries "all"
$CD_CMD && $WP_CMD option update woocommerce_specific_allowed_countries ""

# 2. Reset Shipping Locations to "Ship to all countries you sell to"
$CD_CMD && $WP_CMD option update woocommerce_ship_to_countries "all"

# 3. Reset Currency to USD
$CD_CMD && $WP_CMD option update woocommerce_currency "USD"
$CD_CMD && $WP_CMD option update woocommerce_currency_pos "left"
$CD_CMD && $WP_CMD option update woocommerce_price_thousand_sep ","
$CD_CMD && $WP_CMD option update woocommerce_price_decimal_sep "."

# Flush object cache to ensure settings take effect immediately
$CD_CMD && $WP_CMD cache flush

# Record initial values for anti-gaming verification
echo "Recording initial state..."
$CD_CMD && $WP_CMD option get woocommerce_allowed_countries > /tmp/init_allowed.txt
$CD_CMD && $WP_CMD option get woocommerce_currency > /tmp/init_currency.txt

# Ensure WordPress admin is loaded
echo "Ensuring WordPress admin page is displayed..."
if ! ensure_wordpress_shown 60; then
    echo "FATAL: Could not load WordPress admin page."
    exit 1
fi

# Navigate specifically to the Settings > General tab
# We restart firefox to ensure we are on the right page
pkill -f firefox || true
sleep 1
su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/admin.php?page=wc-settings' &"
sleep 5

# Maximize and Focus
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="