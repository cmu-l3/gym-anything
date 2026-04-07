#!/bin/bash
echo "=== Setting up setup_multilingual_press_releases task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp
date +%s > /tmp/task_start_timestamp
chmod 666 /tmp/task_start_timestamp

# Install Polylang (but don't activate)
echo "Installing Polylang plugin..."
cd /var/www/html/wordpress
wp plugin install polylang --allow-root 2>&1

# Create English category
echo "Creating Press Releases category..."
wp term create category "Press Releases" --allow-root 2>&1
CAT_ID=$(wp term get category "Press Releases" --field=term_id --allow-root 2>/dev/null)

# Create English post
echo "Creating English press release..."
wp post create --post_title="Acquisition of TechCorp Announced" \
    --post_content="We are thrilled to announce the acquisition of TechCorp. This strategic milestone will strengthen our global market presence." \
    --post_category="$CAT_ID" \
    --post_status=publish \
    --allow-root 2>&1

# Ensure Firefox is running
echo "Checking Firefox status..."
if ! pgrep -x "firefox" > /dev/null 2>&1; then
    echo "Firefox not running, starting..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/' > /tmp/firefox_restart.log 2>&1 &"
    sleep 10
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