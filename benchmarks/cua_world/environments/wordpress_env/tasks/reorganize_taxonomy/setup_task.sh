#!/bin/bash
# Setup script for reorganize_taxonomy task (pre_task hook)
# Injects taxonomy issues for the agent to clean up

echo "=== Setting up reorganize_taxonomy task ==="

source /workspace/scripts/task_utils.sh

cd /var/www/html/wordpress

# Ensure Travel and Lifestyle exist as top-level categories
echo "Ensuring base categories exist..."
wp term create category "Travel" --allow-root 2>/dev/null || true
wp term create category "Lifestyle" --allow-root 2>/dev/null || true

TRAVEL_ID=$(wp term list category --name="Travel" --field=term_id --allow-root 2>/dev/null)
LIFESTYLE_ID=$(wp term list category --name="Lifestyle" --field=term_id --allow-root 2>/dev/null)
[ -n "$TRAVEL_ID" ] && wp term update category "$TRAVEL_ID" --parent=0 --allow-root 2>/dev/null
[ -n "$LIFESTYLE_ID" ] && wp term update category "$LIFESTYLE_ID" --parent=0 --allow-root 2>/dev/null

# Delete "Content Hub" if it exists to ensure clean slate
HUB_ID=$(wp term list category --name="Content Hub" --field=term_id --allow-root 2>/dev/null)
[ -n "$HUB_ID" ] && wp term delete category "$HUB_ID" --allow-root 2>/dev/null

# INJECT ISSUE 1: Misspelled Technology category
echo "Injecting typo category..."
wp term create category "Technology" --allow-root 2>/dev/null || true
TECH_ID=$(wp term list category --name="Technology" --field=term_id --allow-root 2>/dev/null)
if [ -n "$TECH_ID" ]; then
    wp term update category "$TECH_ID" --name="Techology" --slug="techology" --parent=0 --allow-root 2>/dev/null
fi

# INJECT ISSUE 2: Empty Miscellaneous category
echo "Injecting empty category..."
wp term create category "Miscellaneous Stuff" --allow-root 2>/dev/null || true

# INJECT ISSUE 3: Unused tag
echo "Injecting unused tag..."
wp term create post_tag "temp-draft-marker" --allow-root 2>/dev/null || true

# INJECT ISSUE 4: Remove 'featured' tag from the 3 most recent posts, record their IDs
echo "Recording 3 most recent posts..."
rm -f /tmp/recent_post_ids.txt
wp post list --post_type=post --post_status=publish --orderby=date --order=DESC --posts_per_page=3 --field=ID --allow-root > /tmp/recent_post_ids.txt

while read -r POST_ID; do
    if [ -n "$POST_ID" ]; then
        # Ensure 'featured' tag is not already on them
        wp post term remove "$POST_ID" post_tag featured --allow-root 2>/dev/null || true
    fi
done < /tmp/recent_post_ids.txt

# Ensure Firefox is running and focused on WordPress admin
echo "Checking Firefox status..."
if ! pgrep -x "firefox" > /dev/null 2>&1; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/' > /tmp/firefox.log 2>&1 &"
    sleep 5
fi

# Focus Firefox window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|wordpress" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot and record start time
take_screenshot /tmp/task_initial.png
date +%s > /tmp/task_start_time
chmod 666 /tmp/task_start_time

echo "=== Task setup complete ==="