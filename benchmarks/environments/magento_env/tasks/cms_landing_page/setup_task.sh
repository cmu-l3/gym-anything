#!/bin/bash
# Setup script for CMS Landing Page task

echo "=== Setting up CMS Landing Page Task ==="

source /workspace/scripts/task_utils.sh

# Record initial CMS counts
echo "Recording initial CMS counts..."
INITIAL_BLOCK_COUNT=$(magento_query "SELECT COUNT(*) FROM cms_block" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")
INITIAL_PAGE_COUNT=$(magento_query "SELECT COUNT(*) FROM cms_page" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")

echo "${INITIAL_BLOCK_COUNT:-0}" > /tmp/initial_cms_block_count
echo "${INITIAL_PAGE_COUNT:-0}" > /tmp/initial_cms_page_count
echo "Initial: blocks=$INITIAL_BLOCK_COUNT pages=$INITIAL_PAGE_COUNT"

# Check if target block or page already exist (for baseline)
EXISTING_BLOCK=$(magento_query "SELECT COUNT(*) FROM cms_block WHERE LOWER(TRIM(identifier))='autumn-collection-featured'" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")
EXISTING_PAGE=$(magento_query "SELECT COUNT(*) FROM cms_page WHERE LOWER(TRIM(identifier))='autumn-collection-2024'" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")
echo "${EXISTING_BLOCK:-0}" > /tmp/autumn_block_exists_at_start
echo "${EXISTING_PAGE:-0}" > /tmp/autumn_page_exists_at_start
echo "Pre-existing: block=$EXISTING_BLOCK page=$EXISTING_PAGE"

# Ensure Firefox is running and logged in
echo "Ensuring Firefox is running..."
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/admin' > /tmp/firefox_task.log 2>&1 &"
    sleep 8
fi

if ! wait_for_window "firefox\|mozilla\|Magento" 30; then
    echo "WARNING: Firefox window not detected"
fi

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 2
fi

WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1)
if echo "$WINDOW_TITLE" | grep -qi "admin" && ! echo "$WINDOW_TITLE" | grep -qi "dashboard"; then
    echo "Attempting login..."
    sleep 2
    DISPLAY=:1 xdotool mousemove 960 540 click 1
    sleep 0.5
    DISPLAY=:1 xdotool key Tab
    sleep 0.3
    DISPLAY=:1 xdotool key ctrl+a
    DISPLAY=:1 xdotool type --clearmodifiers "admin"
    sleep 0.5
    DISPLAY=:1 xdotool key Tab
    sleep 0.3
    DISPLAY=:1 xdotool type --clearmodifiers "Admin1234!"
    sleep 0.5
    DISPLAY=:1 xdotool key Return
    sleep 10
fi

take_screenshot /tmp/task_start_screenshot.png

echo "=== CMS Landing Page Task Setup Complete ==="
echo ""
echo "Navigate to: Content > Elements > Blocks (for Static Block)"
echo "              Content > Pages (for CMS Page)"
echo "Magento Admin: http://localhost/admin  |  admin / Admin1234!"
echo ""
