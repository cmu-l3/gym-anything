#!/bin/bash
# Setup script for configure_seo_optimization task

echo "=== Setting up configure_seo_optimization task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp
date +%s > /tmp/task_start_timestamp
chmod 666 /tmp/task_start_timestamp

# ============================================================
# Install Yoast SEO plugin (download only, do NOT activate)
# ============================================================
echo "Installing Yoast SEO plugin (not activating)..."
cd /var/www/html/wordpress

# Ensure no previous active instance
wp_cli plugin deactivate wordpress-seo 2>/dev/null || true

# Install plugin if not present
wp_cli plugin install wordpress-seo 2>&1
INSTALL_EXIT=$?

if [ $INSTALL_EXIT -ne 0 ]; then
    echo "WARNING: Yoast SEO install via wp-cli failed (exit $INSTALL_EXIT), trying alternative..."
    # Fallback: download directly
    cd /tmp
    curl -sL "https://downloads.wordpress.org/plugin/wordpress-seo.latest-stable.zip" -o yoast.zip 2>/dev/null || \
    wget -q "https://downloads.wordpress.org/plugin/wordpress-seo.latest-stable.zip" -O yoast.zip 2>/dev/null
    if [ -f /tmp/yoast.zip ]; then
        cd /var/www/html/wordpress/wp-content/plugins
        unzip -q -o /tmp/yoast.zip 2>/dev/null
        rm -f /tmp/yoast.zip
        chown -R www-data:www-data /var/www/html/wordpress/wp-content/plugins/wordpress-seo
        echo "Yoast SEO installed via direct download"
    else
        echo "ERROR: Failed to download Yoast SEO"
    fi
fi

# ============================================================
# Ensure target posts exist
# ============================================================
cd /var/www/html/wordpress

ensure_post_exists() {
    local title="$1"
    local content="$2"
    local post_id=$(wp_db_query "SELECT ID FROM wp_posts WHERE post_title='$title' AND post_type='post' AND post_status='publish' LIMIT 1")
    
    if [ -z "$post_id" ]; then
        echo "Creating missing post: '$title'..."
        wp_cli post create --post_type=post --post_status=publish --post_title="$title" --post_content="$content"
    else
        echo "Post exists: '$title' (ID: $post_id)"
    fi
}

ensure_post_exists "Getting Started with WordPress" "Welcome to WordPress! This is your first step into the world of content management systems. WordPress powers over 40% of all websites on the internet, making it the most popular CMS in the world."
ensure_post_exists "10 Essential WordPress Plugins Every Site Needs" "Building a successful WordPress site requires the right tools. Here are our top 10 plugin recommendations for 2024."

# ============================================================
# Clear any pre-existing Yoast metadata
# ============================================================
echo "Clearing existing Yoast metadata to establish clean baseline..."
wp_db_query "DELETE FROM wp_postmeta WHERE meta_key LIKE '_yoast_wpseo_%'"
wp_db_query "DELETE FROM wp_options WHERE option_name LIKE 'wpseo_%'"

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