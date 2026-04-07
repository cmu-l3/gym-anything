#!/bin/bash
# Setup script for create_child_theme task (pre_task hook)

echo "=== Setting up create_child_theme task ==="

# Source utility functions
source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_time.txt
chmod 666 /tmp/task_start_time.txt

# ============================================================
# Clean Environment & Reset to Baseline
# ============================================================
echo "Resetting active theme to Twenty Twenty-Four..."
cd /var/www/html/wordpress

# Ensure parent theme exists and is active
wp theme install twentytwentyfour --activate --allow-root 2>/dev/null || \
wp theme activate twentytwentyfour --allow-root 2>/dev/null || true

# Erase child theme if it existed from a previous run to prevent "do nothing" gaming
THEME_DIR="/var/www/html/wordpress/wp-content/themes/flavor-starter"
if [ -d "$THEME_DIR" ]; then
    echo "Removing existing child theme directory..."
    rm -rf "$THEME_DIR"
fi

# Erase any custom CSS for the child theme in the database
echo "Cleaning up Customizer CSS..."
wp_db_query "DELETE FROM wp_posts WHERE post_type='custom_css' AND post_name='flavor-starter'" 2>/dev/null || true

# ============================================================
# Launch Applications
# ============================================================
echo "Checking Firefox status..."
if ! pgrep -x "firefox" > /dev/null 2>&1; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/themes.php' > /tmp/firefox_task.log 2>&1 &"
    sleep 8
fi

# Focus Firefox window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|wordpress" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Launch a terminal for the agent to create files in
echo "Launching terminal..."
if ! pgrep -x "gnome-terminal-server" > /dev/null 2>&1; then
    su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/var/www/html/wordpress/wp-content/themes &"
    sleep 3
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Agent should now:"
echo "  1. Create the child theme files via terminal"
echo "  2. Activate the theme via WordPress admin"
echo "  3. Apply custom CSS rules"