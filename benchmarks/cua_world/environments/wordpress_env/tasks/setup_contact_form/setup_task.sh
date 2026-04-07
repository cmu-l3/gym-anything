#!/bin/bash
# Setup script for setup_contact_form task

echo "=== Setting up setup_contact_form task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp
date +%s > /tmp/task_start_timestamp
chmod 666 /tmp/task_start_timestamp

# Clean slate: Ensure Contact Form 7 is NOT installed
echo "Removing any existing Contact Form 7 installation..."
cd /var/www/html/wordpress
wp plugin deactivate contact-form-7 --allow-root 2>/dev/null || true
wp plugin delete contact-form-7 --allow-root 2>/dev/null || true

# Clean slate: Ensure no "Contact Us" page exists
echo "Removing any existing 'Contact Us' pages..."
PAGE_IDS=$(wp_db_query "SELECT ID FROM wp_posts WHERE post_title='Contact Us' AND post_type='page'")
for id in $PAGE_IDS; do
    wp post delete "$id" --force --allow-root 2>/dev/null || true
done

# Clean slate: Ensure no "General Inquiry Form" exists
echo "Removing any existing 'General Inquiry Form' forms..."
FORM_IDS=$(wp_db_query "SELECT ID FROM wp_posts WHERE post_title='General Inquiry Form' AND post_type='wpcf7_contact_form'")
for id in $FORM_IDS; do
    wp post delete "$id" --force --allow-root 2>/dev/null || true
done

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
echo "Contact Form 7 is NOT installed. The agent must:"
echo "1. Install and activate it"
echo "2. Create the General Inquiry Form with specific fields"
echo "3. Configure the Mail To address"
echo "4. Create and publish the Contact Us page with the form embedded"