#!/bin/bash
# Setup script for Product Image Watermarking task

echo "=== Setting up Product Image Watermarking Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Admin credentials
ADMIN_USER="admin"
ADMIN_PASS="Admin1234!"

# 1. Create the watermark image file
echo "Creating watermark file..."
mkdir -p /home/ga/Documents
# Create a transparent PNG with text "COPYRIGHT" using ImageMagick
convert -size 200x50 xc:none -fill "rgba(128,128,128,0.5)" -gravity Center -pointsize 24 -annotate 0 "COPYRIGHT" /home/ga/Documents/watermark.png
chown ga:ga /home/ga/Documents/watermark.png
chmod 644 /home/ga/Documents/watermark.png

echo "Watermark created at /home/ga/Documents/watermark.png"

# 2. Record initial config state (optional, just for logging)
echo "Recording initial config state..."
# Check for existing watermarks (should be empty in default install)
magento_query_headers "SELECT path, value FROM core_config_data WHERE path LIKE 'design/watermark%'" > /tmp/initial_watermark_config.txt

# 3. Ensure Firefox is running and focused on Magento admin
echo "Ensuring Firefox is running..."
MAGENTO_ADMIN_URL="http://localhost/admin"

if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$MAGENTO_ADMIN_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 8
fi

# Wait for Firefox window
if ! wait_for_window "firefox\|mozilla\|Magento" 30; then
    echo "WARNING: Firefox window not detected"
fi

# Focus Firefox window
echo "Focusing Firefox window..."
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 2
fi

# Check if we're on the login page
WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1)
echo "Current window: $WINDOW_TITLE"

# Auto-login if needed
if echo "$WINDOW_TITLE" | grep -qi "admin" && ! echo "$WINDOW_TITLE" | grep -qi "dashboard"; then
    echo "Detected login page - attempting to log in..."
    sleep 2
    DISPLAY=:1 xdotool mousemove 960 540 click 1
    sleep 0.5
    DISPLAY=:1 xdotool key Tab
    sleep 0.3
    DISPLAY=:1 xdotool key ctrl+a
    DISPLAY=:1 xdotool type --clearmodifiers "$ADMIN_USER"
    sleep 0.5
    DISPLAY=:1 xdotool key Tab
    sleep 0.3
    DISPLAY=:1 xdotool type --clearmodifiers "$ADMIN_PASS"
    sleep 0.5
    DISPLAY=:1 xdotool key Return
    sleep 10
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo ""
echo "Watermark file prepared: /home/ga/Documents/watermark.png"
echo "Instructions:"
echo "1. Go to Content > Design > Configuration"
echo "2. Edit 'Main Website' scope"
echo "3. Configure Product Image Watermarks (Base, Small, Thumbnail)"
echo "   - Image: Upload /home/ga/Documents/watermark.png"
echo "   - Opacity: 20"
echo "   - Position: Center"
echo ""