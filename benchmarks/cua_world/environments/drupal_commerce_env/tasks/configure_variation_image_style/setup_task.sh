#!/bin/bash
# Setup script for configure_variation_image_style task
echo "=== Setting up configure_variation_image_style ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions if utils not loaded
if ! type drupal_db_query &>/dev/null; then
    drupal_db_query() {
        docker exec drupal-mariadb mysql -u drupal -pdrupalpass drupal -N -e "$1" 2>/dev/null
    }
    take_screenshot() {
        local path="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 scrot "$path" 2>/dev/null || DISPLAY=:1 import -window root "$path" 2>/dev/null || true
    }
    ensure_services_running() {
        echo "Checking services..."
        systemctl start docker 2>/dev/null || true
        docker start drupal-mariadb 2>/dev/null || true
        systemctl start apache2 2>/dev/null || true
    }
    ensure_drupal_shown() {
        echo "Waiting for Drupal..."
        sleep 5
    }
    navigate_firefox_to() {
        local url="$1"
        echo "Navigating to $url"
        DISPLAY=:1 firefox "$url" &
    }
fi

# Ensure services are up
ensure_services_running 120

# RESET STATE: Delete the image style if it exists
echo "Resetting task state..."
drupal_db_query "DELETE FROM config WHERE name = 'image.style.product_main_600'"
# Reset the view display to not use the style (optional, but good for cleanliness)
# We won't fully reset the view display blob as it's complex, but checking timestamps/changes helps.

# Clear Drupal cache to ensure config deletion is recognized
cd /var/www/html/drupal && vendor/bin/drush cr > /dev/null 2>&1 || true

# Record start time
date +%s > /tmp/task_start_timestamp

# Ensure Firefox is open and navigate to Image Styles page
echo "Navigating to Image Styles page..."
navigate_firefox_to "http://localhost/admin/config/media/image-styles"
sleep 5

# Focus and maximize
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="