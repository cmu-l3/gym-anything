#!/bin/bash
# Setup script for configure_custom_editorial_roles task (pre_task hook)

echo "=== Setting up configure_custom_editorial_roles task ==="

# Source utility functions
source /workspace/scripts/task_utils.sh

# Record task start timestamp for verification
date +%s > /tmp/task_start_timestamp
chmod 666 /tmp/task_start_timestamp

echo "Creating initial users with 'author' role..."
cd /var/www/html/wordpress

# Clean up users if they exist from a previous run
for user in sam_taylor alex_rivera jordan_lee; do
    wp user delete "$user" --yes --allow-root 2>/dev/null || true
done

# Clean up the role if it exists from a previous run
wp role delete freelance_writer --allow-root 2>/dev/null || true

# Create the three target users with the default Author role
wp user create sam_taylor sam@example.com --role=author --first_name="Sam" --last_name="Taylor" --allow-root
wp user create alex_rivera alex@example.com --role=author --first_name="Alex" --last_name="Rivera" --allow-root
wp user create jordan_lee jordan@example.com --role=author --first_name="Jordan" --last_name="Lee" --allow-root

echo "Users created successfully."

# Ensure Firefox is running and focused on WordPress admin Users page
echo "Checking Firefox status..."
if ! pgrep -x "firefox" > /dev/null 2>&1; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/users.php' > /tmp/firefox_task.log 2>&1 &"
    sleep 8
fi

# Focus Firefox window and maximize
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|wordpress" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    echo "Firefox window focused: $WID"
else
    echo "WARNING: No Firefox window found!"
fi

# Take initial screenshot as evidence of clean starting state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Target Users (sam_taylor, alex_rivera, jordan_lee) are currently 'Authors'."
echo "Agent must create the 'freelance_writer' role, configure its specific capabilities, and reassign these users."