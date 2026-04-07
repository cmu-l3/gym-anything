#!/bin/bash
# Setup script for convert_to_multisite task (pre_task hook)

echo "=== Setting up convert_to_multisite task ==="

# Source utility functions
source /workspace/scripts/task_utils.sh

# Record task start timestamp (for anti-gaming detection)
date +%s > /tmp/task_start_timestamp
chmod 666 /tmp/task_start_timestamp

# Ensure clean starting state (No existing Multisite config)
WP_CONFIG="/var/www/html/wordpress/wp-config.php"
if grep -qi "WP_ALLOW_MULTISITE" "$WP_CONFIG"; then
    echo "WARNING: WP_ALLOW_MULTISITE already exists in wp-config.php. Cleaning up..."
    sudo sed -i '/WP_ALLOW_MULTISITE/d' "$WP_CONFIG"
    sudo sed -i '/MULTISITE/d' "$WP_CONFIG"
    sudo sed -i '/SUBDOMAIN_INSTALL/d' "$WP_CONFIG"
    sudo sed -i '/DOMAIN_CURRENT_SITE/d' "$WP_CONFIG"
    sudo sed -i '/PATH_CURRENT_SITE/d' "$WP_CONFIG"
    sudo sed -i '/SITE_ID_CURRENT_SITE/d' "$WP_CONFIG"
    sudo sed -i '/BLOG_ID_CURRENT_SITE/d' "$WP_CONFIG"
fi

# Ensure Firefox is running and focused on WordPress admin
echo "Checking Firefox status..."
if ! pgrep -x "firefox" > /dev/null 2>&1; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/' > /tmp/firefox_restart.log 2>&1 &"
    sleep 8
fi

# Open a terminal for the user to edit config files
echo "Opening terminal..."
if ! pgrep -x "gnome-terminal" > /dev/null 2>&1; then
    su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/var/www/html/wordpress &"
    sleep 3
fi

# Organize windows: Focus terminal first, then Firefox (so Firefox is on top)
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true
sleep 0.5
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Agent should now convert the site to a Multisite Network and provision the Biology Department sub-site."