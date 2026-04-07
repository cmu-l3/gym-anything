#!/bin/bash
# Setup script for configure_legal_compliance_pages task

echo "=== Setting up Configure Legal Compliance Pages task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp
chmod 666 /tmp/task_start_timestamp

# ============================================================
# Clean up any existing legal pages & settings to ensure a fresh state
# ============================================================
echo "Cleaning up existing legal pages..."

cd /var/www/html/wordpress

# Find and delete any existing Privacy Policy pages
PRIV_IDS=$(wp_db_query "SELECT ID FROM wp_posts WHERE post_type='page' AND LOWER(post_title) LIKE '%privacy policy%'")
if [ -n "$PRIV_IDS" ]; then
    for ID in $PRIV_IDS; do
        wp post delete "$ID" --force --allow-root 2>/dev/null || true
    done
fi

# Find and delete any existing Terms of Service pages
TOS_IDS=$(wp_db_query "SELECT ID FROM wp_posts WHERE post_type='page' AND LOWER(post_title) LIKE '%terms of service%'")
if [ -n "$TOS_IDS" ]; then
    for ID in $TOS_IDS; do
        wp post delete "$ID" --force --allow-root 2>/dev/null || true
    done
fi

# Reset the privacy policy page option
wp option update wp_page_for_privacy_policy 0 --allow-root 2>/dev/null || true

# Verify cleanup
echo "Cleanup verified. Current privacy policy option: $(wp option get wp_page_for_privacy_policy --allow-root 2>/dev/null || echo '0')"

# ============================================================
# Ensure Firefox is running and focused on WP Admin
# ============================================================
echo "Checking Firefox status..."
if ! pgrep -x "firefox" > /dev/null 2>&1; then
    echo "Firefox not running, starting..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/' > /tmp/firefox.log 2>&1 &"
    sleep 8
fi

# Focus Firefox window and maximize
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|wordpress" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    echo "Firefox window focused."
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="