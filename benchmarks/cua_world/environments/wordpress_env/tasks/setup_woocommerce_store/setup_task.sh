#!/bin/bash
# Setup script for setup_woocommerce_store task (pre_task hook)
# Installs WooCommerce (but does NOT activate it) so the agent can activate and configure.

echo "=== Setting up setup_woocommerce_store task ==="

source /workspace/scripts/task_utils.sh

# ============================================================
# Install WooCommerce plugin (download only, do NOT activate)
# ============================================================
echo "Installing WooCommerce plugin (not activating)..."
cd /var/www/html/wordpress

# Remove any previous WooCommerce installation
wp plugin deactivate woocommerce --allow-root 2>/dev/null || true
wp plugin delete woocommerce --allow-root 2>/dev/null || true

# Install WooCommerce (downloads and extracts, but does not activate)
wp plugin install woocommerce --allow-root 2>&1
INSTALL_EXIT=$?

if [ $INSTALL_EXIT -ne 0 ]; then
    echo "WARNING: WooCommerce install via wp-cli failed (exit $INSTALL_EXIT), trying alternative..."
    # Fallback: download directly
    cd /tmp
    curl -sL "https://downloads.wordpress.org/plugin/woocommerce.latest-stable.zip" -o woocommerce.zip 2>/dev/null || \
    wget -q "https://downloads.wordpress.org/plugin/woocommerce.latest-stable.zip" -O woocommerce.zip 2>/dev/null
    if [ -f /tmp/woocommerce.zip ]; then
        cd /var/www/html/wordpress/wp-content/plugins
        unzip -o /tmp/woocommerce.zip 2>/dev/null
        rm -f /tmp/woocommerce.zip
        chown -R www-data:www-data /var/www/html/wordpress/wp-content/plugins/woocommerce
        echo "WooCommerce installed via direct download"
    else
        echo "ERROR: Failed to download WooCommerce"
    fi
fi

# Verify WooCommerce is installed but not active
cd /var/www/html/wordpress
WC_STATUS=$(wp plugin status woocommerce --allow-root 2>/dev/null | grep -i "status" || echo "unknown")
echo "WooCommerce status: $WC_STATUS"

# Record task start timestamp
date +%s > /tmp/task_start_timestamp
chmod 666 /tmp/task_start_timestamp

# Record baseline: no products, no product categories
INITIAL_PRODUCT_COUNT=0
echo "$INITIAL_PRODUCT_COUNT" | sudo tee /tmp/initial_product_count > /dev/null
sudo chmod 666 /tmp/initial_product_count

# Record WooCommerce active status
echo "inactive" | sudo tee /tmp/initial_wc_status > /dev/null
sudo chmod 666 /tmp/initial_wc_status

# ============================================================
# Ensure Firefox is running
# ============================================================
echo "Checking Firefox status..."
if ! pgrep -x "firefox" > /dev/null 2>&1; then
    echo "Firefox not running, starting..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/?autologin=admin' > /tmp/firefox_restart.log 2>&1 &"
    sleep 10
fi

WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|wordpress" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "WooCommerce installed but NOT activated."
echo "Agent must: activate WooCommerce, create product category, add 3 products, set currency."
