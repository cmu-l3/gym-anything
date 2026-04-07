#!/bin/bash
# Setup script for setup_community_events_calendar task
echo "=== Setting up setup_community_events_calendar task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp
chmod 666 /tmp/task_start_timestamp

# Ensure plugin is NOT already installed (clean slate)
echo "Ensuring The Events Calendar is not pre-installed..."
cd /var/www/html/wordpress
wp plugin deactivate the-events-calendar --allow-root 2>/dev/null || true
wp plugin delete the-events-calendar --allow-root 2>/dev/null || true

# Record initial post counts for the custom post types (should be 0)
INITIAL_VENUE_COUNT=$(wp_db_query "SELECT COUNT(*) FROM wp_posts WHERE post_type='tribe_venue'")
INITIAL_EVENT_COUNT=$(wp_db_query "SELECT COUNT(*) FROM wp_posts WHERE post_type='tribe_events'")
echo "${INITIAL_VENUE_COUNT:-0}" > /tmp/initial_venue_count
echo "${INITIAL_EVENT_COUNT:-0}" > /tmp/initial_event_count

# Create the event schedule file on the Desktop
echo "Creating event schedule data file..."
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/event_schedule.md << 'EOF'
# Summer Event Schedule

## Event 1
**Title:** Summer Reading Kickoff
**Date:** June 1, 2026
**Time:** 10:00 AM - 2:00 PM
**Description:** Join us for the start of the summer reading program with games, crafts, and guest readers.

## Event 2
**Title:** Digital Literacy Workshop
**Date:** June 10, 2026
**Time:** 6:00 PM - 7:30 PM
**Description:** Learn the basics of navigating the internet safely and using library digital resources.

## Event 3
**Title:** Local Author Meet & Greet
**Date:** June 15, 2026
**Time:** 4:00 PM - 5:00 PM
**Description:** Meet local authors, get books signed, and enjoy light refreshments.
EOF
chown ga:ga /home/ga/Desktop/event_schedule.md

# Ensure Firefox is running and focused on WordPress admin
echo "Checking Firefox status..."
if ! pgrep -x "firefox" > /dev/null 2>&1; then
    echo "Firefox not running, starting..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/?autologin=admin' > /tmp/firefox_restart.log 2>&1 &"
    sleep 10
fi

# Maximize and Focus Firefox window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|wordpress" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="