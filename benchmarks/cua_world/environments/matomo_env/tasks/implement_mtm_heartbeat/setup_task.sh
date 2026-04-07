#!/bin/bash
# Setup script for MTM Heartbeat task

echo "=== Setting up MTM Heartbeat Task ==="
source /workspace/scripts/task_utils.sh

# Record task start timestamp (critical for anti-gaming)
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/task_start_timestamp

# Ensure Initial Site exists (ID 1)
echo "Ensuring Initial Site exists..."
SITE_COUNT=$(matomo_query "SELECT COUNT(*) FROM matomo_site WHERE idsite=1" 2>/dev/null || echo "0")
if [ "$SITE_COUNT" = "0" ] || [ -z "$SITE_COUNT" ]; then
    matomo_query "INSERT INTO matomo_site (idsite, name, main_url, ts_created, ecommerce, sitesearch, sitesearch_keyword_parameters, sitesearch_category_parameters, timezone, currency, exclude_unknown_urls, excluded_ips, excluded_parameters, excluded_user_agents, excluded_referrers, \`group\`, type, keep_url_fragment, creator_login) VALUES (1, 'Initial Site', 'https://example.com', NOW(), 0, 1, '', '', 'UTC', 'USD', 0, '', '', '', '', '', 'website', 0, 'admin')" 2>/dev/null
    echo "Initial Site created."
fi

# Clean up ANY existing Tag Manager containers for Site 1
# This ensures the agent must create a new one or at least work from a clean slate
echo "Cleaning up existing containers for site 1..."
# Get container IDs for site 1
CONTAINER_IDS=$(matomo_query "SELECT idcontainer FROM matomo_tagmanager_container WHERE idsite=1" 2>/dev/null)

if [ -n "$CONTAINER_IDS" ]; then
    for cid in $CONTAINER_IDS; do
        echo "Removing container $cid..."
        # Delete related versions, tags, triggers, variables first (cascade usually handles this but being safe)
        matomo_query "DELETE FROM matomo_tagmanager_container_version WHERE idcontainer=$cid" 2>/dev/null || true
        matomo_query "DELETE FROM matomo_tagmanager_tag WHERE idcontainer=$cid" 2>/dev/null || true
        matomo_query "DELETE FROM matomo_tagmanager_trigger WHERE idcontainer=$cid" 2>/dev/null || true
        matomo_query "DELETE FROM matomo_tagmanager_variable WHERE idcontainer=$cid" 2>/dev/null || true
        matomo_query "DELETE FROM matomo_tagmanager_container WHERE idcontainer=$cid" 2>/dev/null || true
    done
fi

# Ensure TagManager plugin is activated (it usually is by default, but good to check)
echo "Ensuring TagManager plugin is active..."
docker exec matomo-app php /var/www/html/console plugin:activate TagManager 2>/dev/null || true

# Start Firefox
echo "Starting Firefox..."
pkill -f firefox 2>/dev/null || true
sleep 1
su - ga -c "DISPLAY=:1 firefox 'http://localhost/' > /tmp/firefox.log 2>&1 &"
sleep 5

# Focus window
if wait_for_window "Matomo" 30; then
    WID=$(get_firefox_window_id)
    if [ -n "$WID" ]; then
        focus_window "$WID"
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi
fi

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="