#!/bin/bash
# Setup script for configure_breaking_news_hub task

echo "=== Setting up breaking_news_hub task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming checks
date +%s | sudo tee /tmp/task_start_timestamp > /dev/null
sudo chmod 666 /tmp/task_start_timestamp

# ============================================================
# Prepare WordPress Environment
# ============================================================
cd /var/www/html/wordpress

# 1. Install and activate Twenty Twenty-One theme 
# (Ensures classic menus are used instead of Full Site Editing)
echo "Setting up classic theme..."
wp theme install twentytwentyone --activate --allow-root 2>/dev/null || true

# 2. Reset Site Tagline to default just in case
wp option update blogdescription "A WordPress blog for testing and demonstrations" --allow-root

# 3. Create Draft Breaking News Post
echo "Creating draft election post..."
# Delete old if exists from previous run
OLD_POST=$(wp post list --post_type=post --title="City Hall Election 2026: Live Results" --field=ID --allow-root 2>/dev/null)
if [ -n "$OLD_POST" ]; then
    wp post delete "$OLD_POST" --force --allow-root 2>/dev/null || true
fi

POST_CONTENT="Early polling numbers show a tighter race than anticipated for the Mayor's office. Voter turnout has been historic across all districts. Stay tuned to this live feed as we update results minute-by-minute."
wp post create --post_type=post \
    --post_title="City Hall Election 2026: Live Results" \
    --post_status=draft \
    --post_content="$POST_CONTENT" \
    --allow-root

# 4. Ensure "News" Category exists and "Breaking News" does not
echo "Configuring categories..."
wp term create category "News" --allow-root 2>/dev/null || true
wp term delete category "Breaking News" --allow-root 2>/dev/null || true
wp term delete category "breaking-news" --by=slug --allow-root 2>/dev/null || true

# 5. Create "Primary Menu" and assign it
echo "Configuring primary menu..."
wp menu delete "Primary Menu" --allow-root 2>/dev/null || true
wp menu create "Primary Menu" --allow-root
wp menu location assign "Primary Menu" primary --allow-root

# 6. Clear sticky posts option
echo "Clearing sticky posts..."
wp option update sticky_posts "[]" --allow-root 2>/dev/null || true

# ============================================================
# Prepare Browser Interface
# ============================================================
echo "Checking Firefox status..."
if ! pgrep -x "firefox" > /dev/null 2>&1; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/' > /tmp/firefox.log 2>&1 &"
    sleep 8
fi

# Focus and Maximize Firefox window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|wordpress" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    echo "Firefox window focused: $WID"
fi

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="