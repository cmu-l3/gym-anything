#!/bin/bash
# Setup script for harden_security_and_backups task

echo "=== Setting up harden_security_and_backups task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp
date +%s > /tmp/task_start_timestamp
chmod 666 /tmp/task_start_timestamp

# ============================================================
# Prepare initial state
# ============================================================

# 1. Ensure 'admin' user exists and has posts
ADMIN_ID=$(wp_db_query "SELECT ID FROM wp_users WHERE user_login='admin' LIMIT 1" 2>/dev/null)
if [ -z "$ADMIN_ID" ]; then
    echo "Creating missing admin user..."
    wp_cli user create admin admin@example.com --role=administrator --user_pass=Admin1234!
    ADMIN_ID=$(wp_db_query "SELECT ID FROM wp_users WHERE user_login='admin' LIMIT 1")
fi

# Make sure admin has some posts assigned to them (should be true from Theme Unit Test, but enforce it)
wp_db_query "UPDATE wp_posts SET post_author=$ADMIN_ID WHERE post_type IN ('post', 'page') AND post_status='publish' LIMIT 10" > /dev/null 2>&1

ADMIN_POST_COUNT=$(wp_db_query "SELECT COUNT(*) FROM wp_posts WHERE post_author=$ADMIN_ID AND post_type IN ('post', 'page') AND post_status='publish'" 2>/dev/null)
echo "Admin user ID: $ADMIN_ID with $ADMIN_POST_COUNT published posts/pages"

# Record baseline for verification
echo "$ADMIN_POST_COUNT" > /tmp/initial_admin_post_count
chmod 666 /tmp/initial_admin_post_count

# 2. Ensure 'sec_admin' does NOT exist from previous runs
if user_exists "sec_admin"; then
    echo "Removing existing sec_admin for clean slate..."
    cd /var/www/html/wordpress
    wp user delete sec_admin --yes --allow-root 2>/dev/null || true
fi

# 3. Ensure DISALLOW_FILE_EDIT is not set in wp-config.php
echo "Cleaning wp-config.php..."
sed -i '/DISALLOW_FILE_EDIT/d' /var/www/html/wordpress/wp-config.php

# 4. Ensure UpdraftPlus is not installed/active
echo "Removing UpdraftPlus if exists..."
wp_cli plugin deactivate updraftplus 2>/dev/null || true
wp_cli plugin delete updraftplus 2>/dev/null || true

# ============================================================
# Launch Firefox
# ============================================================
echo "Checking Firefox status..."
if ! pgrep -x "firefox" > /dev/null 2>&1; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/' > /tmp/firefox_restart.log 2>&1 &"
    sleep 8
fi

# Focus Firefox window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|wordpress" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    echo "Firefox window focused: $WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="