#!/bin/bash
echo "=== Setting up whitelabel_wp_login task ==="

source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt
chmod 666 /tmp/task_start_time.txt

# Create client assets directory
mkdir -p /home/ga/client-assets

# Download a CC0 sample logo (e.g., from Wikimedia Commons)
LOGO_PATH="/home/ga/client-assets/client-logo.png"
curl -sL "https://upload.wikimedia.org/wikipedia/commons/thumb/a/a7/React-icon.svg/256px-React-icon.svg.png" -o "$LOGO_PATH" 2>/dev/null || \
wget -q "https://upload.wikimedia.org/wikipedia/commons/thumb/a/a7/React-icon.svg/256px-React-icon.svg.png" -O "$LOGO_PATH" 2>/dev/null

if [ ! -s "$LOGO_PATH" ]; then
    # Fallback to a tiny base64 encoded PNG if download fails
    echo "Fallback logo creation..."
    echo "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==" | base64 -d > "$LOGO_PATH"
fi

chown -R ga:ga /home/ga/client-assets
chmod 644 "$LOGO_PATH"

# Ensure mu-plugins directory does NOT exist initially (clean state)
rm -rf /var/www/html/wordpress/wp-content/mu-plugins 2>/dev/null || sudo rm -rf /var/www/html/wordpress/wp-content/mu-plugins 2>/dev/null || true

# Check if Firefox is running
if ! pgrep -x "firefox" > /dev/null 2>&1; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-login.php' > /tmp/firefox_restart.log 2>&1 &"
    sleep 10
else
    su - ga -c "DISPLAY=:1 firefox --new-window 'http://localhost/wp-login.php' &"
    sleep 5
fi

# Focus Firefox window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|wordpress" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

take_screenshot /tmp/task_initial.png
echo "=== Setup complete ==="