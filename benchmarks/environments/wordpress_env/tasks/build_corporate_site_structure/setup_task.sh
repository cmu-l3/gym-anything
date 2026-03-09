#!/bin/bash
# Setup script for build_corporate_site_structure task (pre_task hook)
# Records baseline page state. Does NOT pre-create any pages.

echo "=== Setting up build_corporate_site_structure task ==="

source /workspace/scripts/task_utils.sh

# Record initial page count
INITIAL_PAGE_COUNT=$(get_post_count "page" "publish")
echo "$INITIAL_PAGE_COUNT" | sudo tee /tmp/initial_page_count > /dev/null
sudo chmod 666 /tmp/initial_page_count
echo "Initial published page count: $INITIAL_PAGE_COUNT"

# Record initial reading settings
SHOW_ON_FRONT=$(wp_cli option get show_on_front)
PAGE_ON_FRONT=$(wp_cli option get page_on_front)
echo "Initial show_on_front: $SHOW_ON_FRONT"
echo "Initial page_on_front: $PAGE_ON_FRONT"

# Record initial site title/tagline
ORIG_TITLE=$(wp_cli option get blogname)
ORIG_TAGLINE=$(wp_cli option get blogdescription)
echo "Initial site title: $ORIG_TITLE"
echo "Initial tagline: $ORIG_TAGLINE"

# Save baseline
cat > /tmp/corporate_site_baseline.json << BASEEOF
{
    "initial_page_count": $INITIAL_PAGE_COUNT,
    "initial_show_on_front": "$SHOW_ON_FRONT",
    "initial_page_on_front": "$PAGE_ON_FRONT",
    "initial_blogname": "$(json_escape "$ORIG_TITLE")",
    "initial_blogdescription": "$(json_escape "$ORIG_TAGLINE")"
}
BASEEOF
chmod 666 /tmp/corporate_site_baseline.json

# Record task start timestamp
date +%s > /tmp/task_start_timestamp
chmod 666 /tmp/task_start_timestamp

# List existing pages
echo ""
echo "Existing pages:"
wp_cli post list --post_type=page --post_status=publish --fields=ID,post_title,post_parent

# Ensure Firefox is running
echo ""
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
echo "Agent must create 6 pages with hierarchy, set static front page, update site title."
