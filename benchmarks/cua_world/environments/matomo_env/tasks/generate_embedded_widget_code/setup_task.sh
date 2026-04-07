#!/bin/bash
# Setup script for Generate Embedded Widget Code task

echo "=== Setting up Generate Embedded Widget Code Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start timestamp (critical for anti-gaming)
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/task_start_timestamp
echo "Task start timestamp: $TASK_START"

# Ensure Initial Site exists (ID 1)
echo "Ensuring Initial Site exists..."
SITE_COUNT=$(matomo_query "SELECT COUNT(*) FROM matomo_site WHERE idsite=1" 2>/dev/null || echo "0")

if [ "$SITE_COUNT" = "0" ] || [ -z "$SITE_COUNT" ]; then
    echo "Creating Initial Site..."
    matomo_query "INSERT INTO matomo_site (idsite, name, main_url, ts_created, ecommerce, sitesearch, sitesearch_keyword_parameters, sitesearch_category_parameters, timezone, currency, exclude_unknown_urls, excluded_ips, excluded_parameters, excluded_user_agents, excluded_referrers, \`group\`, type, keep_url_fragment, creator_login)
                  VALUES (1, 'Initial Site', 'https://example.com', NOW(), 0, 1, '', '', 'UTC', 'USD', 0, '', '', '', '', '', 'website', 0, 'admin')" 2>/dev/null
    echo "Initial Site created"
fi

# Ensure Firefox is running on Matomo Dashboard
echo "Ensuring Firefox is running..."
MATOMO_URL="http://localhost/"

# Kill any existing Firefox instances for clean start
pkill -f firefox 2>/dev/null || true
sleep 2

echo "Starting Firefox..."
su - ga -c "DISPLAY=:1 firefox '$MATOMO_URL' > /tmp/firefox_task.log 2>&1 &"
sleep 5

# Wait for Firefox window
if ! wait_for_window "firefox\|mozilla\|Matomo" 30; then
    echo "WARNING: Firefox window not detected"
fi

# Focus and maximize Firefox window
echo "Focusing Firefox window..."
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Dismiss any Firefox first-run dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5

# Take initial screenshot for audit
take_screenshot /tmp/task_initial_screenshot.png

echo ""
echo "=== Setup Complete ==="
echo "Task: Generate embed code for 'Visits Over Time' widget (Site 1) WITH auth token."
echo "Save to: /home/ga/intranet_widget_code.html"