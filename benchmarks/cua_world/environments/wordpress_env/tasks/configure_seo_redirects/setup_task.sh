#!/bin/bash
# Setup script for configure_seo_redirects task
echo "=== Setting up configure_seo_redirects task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp
date +%s > /tmp/task_start_timestamp
chmod 666 /tmp/task_start_timestamp

# Ensure required target pages exist so they return HTTP 200 natively
echo "Creating target destination pages..."
cd /var/www/html/wordpress
wp post create --post_type=page --post_title="About Us" --post_name="about-us" --post_status=publish --allow-root 2>&1
wp post create --post_type=page --post_title="Services" --post_name="services" --post_status=publish --allow-root 2>&1
wp post create --post_type=page --post_title="Contact" --post_name="contact" --post_status=publish --allow-root 2>&1

# Create the News category (wp term create returns error if it already exists, so ignore failure)
wp term create category "News" --slug="news" --allow-root 2>/dev/null || true

# Make .htaccess explicitly writable by the 'ga' user to allow direct file modification
chmod 666 /var/www/html/wordpress/.htaccess

# Ensure Firefox is running and focused on WordPress admin
echo "Checking Firefox status..."
if ! pgrep -x "firefox" > /dev/null 2>&1; then
    echo "Firefox not running, starting..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/' > /tmp/firefox.log 2>&1 &"
    sleep 10
fi

# Bring Firefox to the front and maximize
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|wordpress" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Agent should now configure the four 301 redirects."