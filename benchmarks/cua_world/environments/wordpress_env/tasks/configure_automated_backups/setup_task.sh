#!/bin/bash
echo "=== Setting up configure_automated_backups task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming (ensures backups were created during task)
date +%s > /tmp/task_start_timestamp
chmod 666 /tmp/task_start_timestamp

# Create the dummy directory and massive uncompressible file
# If the agent fails to exclude this directory, the zip file will be > 50MB
echo "Creating massive dummy directory to test exclusion rules..."
TARGET_DIR="/var/www/html/wordpress/wp-content/uploads/temp-video-renders"
mkdir -p "$TARGET_DIR"

# Generate 50MB of random data (uncompressible)
dd if=/dev/urandom of="$TARGET_DIR/huge-video.mkv" bs=1M count=50 2>/dev/null
chown -R www-data:www-data /var/www/html/wordpress/wp-content/uploads

# Clean up any existing updraft backups or configurations
echo "Cleaning up any existing backups..."
rm -rf /var/www/html/wordpress/wp-content/updraft/* 2>/dev/null || true

# Uninstall UpdraftPlus if it exists from a previous run
cd /var/www/html/wordpress
wp plugin deactivate updraftplus --allow-root 2>/dev/null || true
wp plugin delete updraftplus --allow-root 2>/dev/null || true

# Ensure Firefox is running
echo "Checking Firefox status..."
if ! pgrep -x "firefox" > /dev/null 2>&1; then
    echo "Firefox not running, starting..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/' > /tmp/firefox_restart.log 2>&1 &"
    sleep 10
fi

# Focus Firefox
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|wordpress" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="