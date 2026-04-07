#!/bin/bash
# Setup script for optimize_database_bloat_and_autoload task
# Injects database bloat and configuration traps

echo "=== Setting up optimize_database_bloat_and_autoload task ==="

# Source utility functions
source /workspace/scripts/task_utils.sh

# Record task start timestamp
date +%s > /tmp/task_start_time.txt
chmod 666 /tmp/task_start_time.txt

cd /var/www/html/wordpress

echo "Injecting database bloat..."

# 1. Create abandoned table
wp_db_query "CREATE TABLE IF NOT EXISTS wp_abandoned_plugin_logs (
    id INT AUTO_INCREMENT PRIMARY KEY,
    log_data TEXT,
    created_at DATETIME
);"
wp_db_query "INSERT INTO wp_abandoned_plugin_logs (log_data, created_at) VALUES 
    ('Legacy error log 1', NOW()), 
    ('Legacy error log 2', NOW());"

# 2. Insert fake transients
wp_db_query "INSERT INTO wp_options (option_name, option_value, autoload) VALUES 
    ('_transient_timeout_old_cache_1', '1234567890', 'yes'), 
    ('_transient_old_cache_1', 'expired_data', 'yes'),
    ('_transient_timeout_old_cache_2', '1234567890', 'yes'),
    ('_transient_old_cache_2', 'expired_data', 'yes');"

# 3. Insert massive autoload trap
# Using a 50KB string to simulate a heavy autoload option
wp_db_query "INSERT INTO wp_options (option_name, option_value, autoload) 
    VALUES ('_legacy_theme_cache_data', REPEAT('A', 50000), 'yes') 
    ON DUPLICATE KEY UPDATE autoload='yes', option_value=REPEAT('A', 50000);"

# 4. Create post revisions
echo "Creating post revisions..."
POST_ID=$(wp post create --post_type=post --post_title="Drafting a Post" --post_content="Content v1" --post_status=publish --porcelain --allow-root 2>/dev/null)
if [ -n "$POST_ID" ]; then
    wp post update "$POST_ID" --post_content="Content v2" --allow-root 2>/dev/null
    wp post update "$POST_ID" --post_content="Content v3" --allow-root 2>/dev/null
    wp post update "$POST_ID" --post_content="Content v4" --allow-root 2>/dev/null
fi

# 5. Insert orphaned metadata (assigning to non-existent post IDs like 999998, 999999)
wp_db_query "INSERT INTO wp_postmeta (post_id, meta_key, meta_value) VALUES 
    (999999, '_edit_lock', '123456:1'), 
    (999999, '_thumbnail_id', '5'), 
    (999998, 'old_plugin_data', 'junk'),
    (999997, '_yoast_wpseo_focuskw', 'test');"

# Record baseline for verification
INITIAL_ORPHANS=$(wp_db_query "SELECT COUNT(*) FROM wp_postmeta pm LEFT JOIN wp_posts wp ON pm.post_id = wp.ID WHERE wp.ID IS NULL;" 2>/dev/null)
INITIAL_TRANSIENTS=$(wp_db_query "SELECT COUNT(*) FROM wp_options WHERE option_name LIKE '%_transient_%';" 2>/dev/null)
INITIAL_REVISIONS=$(wp_db_query "SELECT COUNT(*) FROM wp_posts WHERE post_type = 'revision';" 2>/dev/null)

echo "Baseline recorded:"
echo "- Orphaned metadata: $INITIAL_ORPHANS"
echo "- Transients: $INITIAL_TRANSIENTS"
echo "- Revisions: $INITIAL_REVISIONS"

# Start Firefox and focus Terminal
if ! pgrep -x "firefox" > /dev/null 2>&1; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/' > /tmp/firefox_restart.log 2>&1 &"
    sleep 5
fi

# Launch a terminal for the user (since DB operations are expected)
su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/var/www/html/wordpress &"
sleep 2

# Focus terminal
WID=$(DISPLAY=:1 wmctrl -l | grep -i "terminal" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="