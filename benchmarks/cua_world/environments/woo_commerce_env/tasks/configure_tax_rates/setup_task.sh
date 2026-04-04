#!/bin/bash
set -e
echo "=== Setting up Configure Tax Rates Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure database is accessible
if ! check_db_connection; then
    echo "ERROR: Database connection failed."
    exit 1
fi

# 1. Clear existing tax rates to ensure a clean slate
# We delete from both tables to avoid foreign key constraints or orphaned data
echo "Clearing existing tax rates..."
wc_query "DELETE FROM wp_woocommerce_tax_rate_locations" 2>/dev/null || true
wc_query "DELETE FROM wp_woocommerce_tax_rates" 2>/dev/null || true

# 2. Reset Tax Options to 'wrong' defaults so the agent has to change them
# We enable tax calculation generally, but set specific options to values different from the goal
echo "Resetting tax options..."
cd /var/www/html/wordpress
wp option update woocommerce_calc_taxes "yes" --allow-root 2>&1
wp option update woocommerce_prices_include_tax "yes" --allow-root 2>&1  # Goal: no
wp option update woocommerce_tax_based_on "base" --allow-root 2>&1      # Goal: shipping
wp option update woocommerce_tax_display_shop "incl" --allow-root 2>&1   # Goal: excl
wp option update woocommerce_tax_display_cart "incl" --allow-root 2>&1   # Goal: excl

# 3. Ensure WordPress admin is loaded
echo "Ensuring WordPress admin page is displayed..."
if ! ensure_wordpress_shown 60; then
    echo "FATAL: Could not load WordPress admin page."
    exit 1
fi

# 4. Focus and maximize Firefox
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Tax rates cleared. Options reset. Firefox focused."