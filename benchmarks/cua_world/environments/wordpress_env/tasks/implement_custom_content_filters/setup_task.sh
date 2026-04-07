#!/bin/bash
# Setup script for implement_custom_content_filters task

echo "=== Setting up implement_custom_content_filters task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt
chmod 666 /tmp/task_start_time.txt

# ============================================================
# Create and activate child theme
# ============================================================
echo "Setting up Magazine Child theme..."
CHILD_DIR="/var/www/html/wordpress/wp-content/themes/magazine-child"
mkdir -p "$CHILD_DIR"

cat > "$CHILD_DIR/style.css" << 'EOF'
/*
Theme Name: Magazine Child
Template: twentytwentyfour
Description: A child theme for custom functional testing.
*/
EOF

cat > "$CHILD_DIR/functions.php" << 'EOF'
<?php
// Exit if accessed directly
if ( !defined( 'ABSPATH' ) ) exit;

// Add your custom content filters below this line:

EOF

chown -R www-data:www-data "$CHILD_DIR"
chmod -R 755 "$CHILD_DIR"

# Activate the child theme
cd /var/www/html/wordpress
wp_cli theme activate magazine-child

# ============================================================
# Create categories and sample posts for the agent to test with
# ============================================================
echo "Creating categories and sample data..."

HEALTH_CAT_ID=$(wp_cli term create category "Health" --porcelain 2>/dev/null || wp_cli term get category health --field=term_id)
TECH_CAT_ID=$(wp_cli term create category "Technology" --porcelain 2>/dev/null || wp_cli term get category technology --field=term_id)

wp_cli post create --post_title="The Benefits of Daily Exercise" \
    --post_content="Exercise is extremely important for cardiovascular health. It improves blood flow and heart function. This is a short post meant to demonstrate the health category." \
    --post_category="$HEALTH_CAT_ID" \
    --post_status="publish"

wp_cli post create --post_title="New CPU Architectures Unveiled" \
    --post_content="Tech companies have revealed new silicon architecture that improves processing power by twenty percent while reducing thermal output. This is a sample tech post." \
    --post_category="$TECH_CAT_ID" \
    --post_status="publish"

# ============================================================
# Ensure Firefox is running and focused on Theme Editor
# ============================================================
echo "Checking Firefox status..."
if ! pgrep -x "firefox" > /dev/null 2>&1; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/theme-editor.php' > /tmp/firefox_restart.log 2>&1 &"
    sleep 8
fi

# Focus Firefox window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|wordpress" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="