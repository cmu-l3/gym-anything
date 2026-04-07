#!/bin/bash
# Setup script for resolve_fatal_error_and_optimize task

echo "=== Setting up resolve_fatal_error_and_optimize task ==="

source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt
chmod 666 /tmp/task_start_time.txt

cd /var/www/html/wordpress

# ============================================================
# 1. Generate Valid and Spam Comments
# ============================================================
echo "Generating comments..."
# Ensure at least one post exists
POST_ID=$(wp_db_query "SELECT ID FROM wp_posts WHERE post_type='post' AND post_status='publish' LIMIT 1")
if [ -z "$POST_ID" ]; then
    POST_ID=$(wp post create --post_title="Welcome to our blog" --post_content="Hello world" --post_status="publish" --porcelain --allow-root)
fi

# Add valid comments
for i in {1..3}; do
    wp comment create --comment_post_ID="$POST_ID" --comment_author="ValidUser$i" --comment_content="This is a great, helpful comment." --comment_approved=1 --allow-root >/dev/null
done

# Add spam comments
for i in {1..12}; do
    wp comment create --comment_post_ID="$POST_ID" --comment_author="SpamBot$i" --comment_content="Buy cheap meds here $i http://spam.xyz" --comment_approved=spam --allow-root >/dev/null
done

# ============================================================
# 2. Generate Post Revisions
# ============================================================
echo "Generating post revisions..."
REV_POST_ID=$(wp post create --post_title="Drafting a big post" --post_content="Initial draft." --post_status="publish" --porcelain --allow-root)

for i in {1..8}; do
    wp post update "$REV_POST_ID" --post_content="Update iteration $i with more content..." --allow-root >/dev/null
done

# ============================================================
# 3. Create and Activate Rogue Plugin (Causes Fatal Error)
# ============================================================
echo "Deploying rogue plugin..."
PLUGIN_DIR="/var/www/html/wordpress/wp-content/plugins/broken-analytics"
mkdir -p "$PLUGIN_DIR"

# Step 3a: Create a valid version first so WP-CLI can activate it safely
cat > "$PLUGIN_DIR/broken-analytics.php" << 'EOF'
<?php
/*
Plugin Name: Broken Analytics
Description: An analytics plugin that recently updated.
Version: 2.0
*/
EOF
chown -R www-data:www-data "$PLUGIN_DIR"

# Activate it
wp plugin activate broken-analytics --allow-root

# Step 3b: Overwrite with the fatally broken version
cat > "$PLUGIN_DIR/broken-analytics.php" << 'EOF'
<?php
/*
Plugin Name: Broken Analytics
Description: An analytics plugin that recently updated.
Version: 2.0
*/
// This will cause a fatal error on every page load and in WP-CLI
trigger_fatal_error_to_crash_site_completely();
EOF
chown -R www-data:www-data "$PLUGIN_DIR"

# ============================================================
# 4. Prepare UI (Terminal + Broken Webpage)
# ============================================================
echo "Opening terminal and browser..."

# Open terminal for agent
if ! pgrep -x "gnome-terminal-server" > /dev/null 2>&1; then
    su - ga -c "DISPLAY=:1 gnome-terminal &"
    sleep 3
fi

# Open Firefox to the broken site
if ! pgrep -x "firefox" > /dev/null 2>&1; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/' > /tmp/firefox_restart.log 2>&1 &"
    sleep 5
fi

# Arrange windows
WID_TERM=$(DISPLAY=:1 wmctrl -l | grep -i "Terminal" | head -1 | awk '{print $1}')
WID_FF=$(DISPLAY=:1 wmctrl -l | grep -i "Firefox" | head -1 | awk '{print $1}')

if [ -n "$WID_FF" ]; then
    DISPLAY=:1 wmctrl -ia "$WID_FF" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Bring terminal to front over firefox so agent sees it
if [ -n "$WID_TERM" ]; then
    DISPLAY=:1 wmctrl -ia "$WID_TERM" 2>/dev/null || true
fi

# Take initial screenshot showing the 500 error / white screen in background and terminal in foreground
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Site is currently crashed. Terminal is ready for the agent."