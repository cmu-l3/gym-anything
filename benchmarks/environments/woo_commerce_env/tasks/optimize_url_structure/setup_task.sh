#!/bin/bash
set -e
echo "=== Setting up task: optimize_url_structure ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for database/WordPress to be ready
echo "Waiting for WordPress..."
for i in {1..30}; do
    if check_db_connection; then
        break
    fi
    sleep 2
done

# CRITICAL: Ensure we start with DEFAULT settings (Anti-gaming)
# If the setting is already correct, the agent might get free points.
echo "Resetting permalinks to defaults..."
wp option update woocommerce_permalinks '{"category_base":"","tag_base":"","attribute_base":"","product_base":"/product/"}' --format=json --allow-root --path=/var/www/html/wordpress 2>/dev/null

# Flush rewrite rules to ensure clean state
wp rewrite flush --allow-root --path=/var/www/html/wordpress 2>/dev/null

# Record initial state for "do nothing" detection
INITIAL_PERMALINKS=$(wp option get woocommerce_permalinks --format=json --allow-root --path=/var/www/html/wordpress 2>/dev/null)
echo "$INITIAL_PERMALINKS" > /tmp/initial_permalinks.json
echo "Initial settings recorded: $INITIAL_PERMALINKS"

# Ensure WordPress admin is loaded in Firefox
# We start at the Dashboard to test navigation to Settings > Permalinks
echo "Ensuring WordPress admin page is displayed..."
if ! ensure_wordpress_shown 60; then
    echo "FATAL: Could not load WordPress admin page."
    exit 1
fi

# Focus and maximize Firefox
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="