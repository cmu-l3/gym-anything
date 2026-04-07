#!/bin/bash
# Setup script for Matomo Tag Manager task

echo "=== Setting up Tag Manager Task ==="
source /workspace/scripts/task_utils.sh

# 1. Ensure 'Initial Site' exists (ID 1)
echo "Ensuring Initial Site exists..."
SITE_COUNT=$(matomo_query "SELECT COUNT(*) FROM matomo_site WHERE idsite=1" 2>/dev/null || echo "0")
if [ "$SITE_COUNT" = "0" ]; then
    matomo_query "INSERT INTO matomo_site (idsite, name, main_url, ts_created, ecommerce, sitesearch, sitesearch_keyword_parameters, sitesearch_category_parameters, timezone, currency, exclude_unknown_urls, excluded_ips, excluded_parameters, excluded_user_agents, excluded_referrers, \`group\`, type, keep_url_fragment, creator_login) VALUES (1, 'Initial Site', 'https://example.com', NOW(), 0, 1, '', '', 'UTC', 'USD', 0, '', '', '', '', '', 'website', 0, 'admin')" 2>/dev/null
fi

# 2. Clean up any existing Tag Manager data for Site 1 to ensure a fresh start
# This prevents ambiguity if the agent just renames an existing tag
echo "Cleaning up existing Tag Manager containers for Site 1..."
# Note: In a real prod env we wouldn't delete, but for a task we want a clean slate or known state.
# Deleting the container cascades to tags/triggers usually, but we'll be safe.
matomo_query "DELETE FROM matomo_tagmanager_container WHERE idsite=1" 2>/dev/null || true
matomo_query "DELETE FROM matomo_tagmanager_tag WHERE idsite=1" 2>/dev/null || true
matomo_query "DELETE FROM matomo_tagmanager_trigger WHERE idsite=1" 2>/dev/null || true
matomo_query "DELETE FROM matomo_tagmanager_container_version WHERE idsite=1" 2>/dev/null || true

# 3. Record task start timestamp
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/task_start_timestamp
echo "Task start timestamp: $TASK_START"

# 4. Launch Firefox
echo "Starting Firefox..."
pkill -f firefox 2>/dev/null || true
sleep 2

# Matomo URL
MATOMO_URL="http://localhost/"

su - ga -c "DISPLAY=:1 firefox '$MATOMO_URL' > /tmp/firefox_task.log 2>&1 &"
sleep 5

if ! wait_for_window "firefox\|mozilla\|Matomo" 30; then
    echo "WARNING: Firefox window not detected"
fi

# Focus and maximize
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 5. Take initial screenshot
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Tag Manager Task Setup Complete ==="