#!/bin/bash
# Setup script for diagnose_performance_bottleneck_and_cache
# Injects a rogue plugin that deliberately sleeps for 5 seconds on every request

echo "=== Setting up diagnose_performance_bottleneck_and_cache task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp
date +%s > /tmp/task_start_timestamp
chmod 666 /tmp/task_start_timestamp

# ============================================================
# INJECT ISSUE: Create and activate rogue plugin
# ============================================================
echo "Injecting rogue plugin (WP Social Share Pro)..."
PLUGIN_DIR="/var/www/html/wordpress/wp-content/plugins/wp-social-share-pro"
mkdir -p "$PLUGIN_DIR"

cat > "$PLUGIN_DIR/wp-social-share-pro.php" << 'EOF'
<?php
/*
Plugin Name: WP Social Share Pro
Description: Adds social sharing buttons and fetches live share counts from Twitter, Facebook, and LinkedIn.
Version: 1.2.4
Author: Marketing Contractor
*/

// Deliberately delay execution by 5 seconds to simulate a blocking third-party API call
add_action('init', function() {
    sleep(5);
});
EOF

chown -R www-data:www-data "$PLUGIN_DIR"

cd /var/www/html/wordpress
# Activate the rogue plugin
wp plugin activate wp-social-share-pro --allow-root 2>&1

# Ensure wordpress-importer is installed and active (as a control)
wp plugin install wordpress-importer --activate --allow-root 2>/dev/null || true

# Pre-delete wp-super-cache if it exists to ensure agent has to install it
wp plugin deactivate wp-super-cache --allow-root 2>/dev/null || true
wp plugin delete wp-super-cache --allow-root 2>/dev/null || true

# Remove WP_CACHE from wp-config.php if it exists from previous runs
sed -i '/WP_CACHE/d' /var/www/html/wordpress/wp-config.php

echo "Rogue plugin injected and activated. Site will now be extremely slow."

# ============================================================
# Ensure Firefox is running
# ============================================================
echo "Checking Firefox status..."
if ! pgrep -x "firefox" > /dev/null 2>&1; then
    echo "Firefox not running, starting..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/' > /tmp/firefox_restart.log 2>&1 &"
    # Need to wait longer because the site itself takes 5+ seconds to load now
    sleep 15
fi

WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|wordpress" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Agent must diagnose the slow load time, disable 'WP Social Share Pro', and install/configure 'WP Super Cache'."