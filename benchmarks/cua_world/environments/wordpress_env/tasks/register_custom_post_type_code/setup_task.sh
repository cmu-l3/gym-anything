#!/bin/bash
echo "=== Setting up Custom Post Type task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# ============================================================
# 1. Setup the Child Theme
# ============================================================
echo "Creating Agency Child theme..."
THEME_DIR="/var/www/html/wordpress/wp-content/themes/agency-child"
mkdir -p "$THEME_DIR"

cat > "$THEME_DIR/style.css" << 'EOF'
/*
Theme Name: Agency Child
Template: twentytwentyfour
Description: A child theme for our digital agency.
Version: 1.0.0
*/
EOF

cat > "$THEME_DIR/functions.php" << 'EOF'
<?php
// Agency Child Theme Functions
add_action( 'wp_enqueue_scripts', 'agency_child_enqueue_styles' );
function agency_child_enqueue_styles() {
    wp_enqueue_style( 'parent-style', get_template_directory_uri() . '/style.css' );
}

// Add your custom post types below this line:

EOF

chown -R www-data:www-data "$THEME_DIR"
chmod -R 755 "$THEME_DIR"

# Activate the child theme
cd /var/www/html/wordpress
wp theme activate agency-child --allow-root 2>&1

# Record the initial modification time of functions.php
stat -c %Y "$THEME_DIR/functions.php" > /tmp/functions_initial_mtime.txt

# ============================================================
# 2. Setup Real Data Assets
# ============================================================
echo "Creating Portfolio Assets..."
ASSETS_DIR="/home/ga/Documents/Portfolio_Assets"
mkdir -p "$ASSETS_DIR"

cat > "$ASSETS_DIR/project_description.txt" << 'EOF'
The NASA Graphics Standards Manual by Richard Danne and Bruce Blackburn is a futuristic vision for an agency at the cutting edge of science and exploration. This restoration project meticulously digitizes the original 1975 documentation, ensuring the iconic "worm" logo and its associated design system are preserved for future generations of designers.

We used high-resolution scanning equipment to capture the original ring-bound manual, correcting for color degradation and paper yellowing while maintaining the historical accuracy of the original Pantone matching system colors. The result is a faithful digital reproduction that honors the modernist heritage of the space program.
EOF

# Create a valid 1x1 red PNG file for the featured image using base64
echo "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==" | base64 -d > "$ASSETS_DIR/featured_image.png"

chown -R ga:ga "$ASSETS_DIR"

# ============================================================
# 3. Ensure Environment State
# ============================================================
# Delete any existing portfolio posts just in case of a retry
wp post delete $(wp post list --post_type=portfolio --format=ids --allow-root 2>/dev/null) --force --allow-root 2>/dev/null || true

# Check if Firefox is running, if not start it pointing to admin
if ! pgrep -x "firefox" > /dev/null 2>&1; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/' > /tmp/firefox.log 2>&1 &"
    sleep 5
fi

# Focus and maximize Firefox
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|wordpress" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Dismiss any immediate popups
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Capture initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="