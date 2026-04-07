#!/bin/bash
# Setup script for MTM CTA Tracking task

echo "=== Setting up MTM CTA Tracking Task ==="
source /workspace/scripts/task_utils.sh

# 1. Ensure Matomo is ready
if ! matomo_is_installed; then
    echo "Matomo not fully installed. Running automated setup..."
    /workspace/scripts/setup_matomo.sh
fi

# 2. Ensure Initial Site exists
if ! site_exists "Initial Site"; then
    echo "Creating Initial Site..."
    matomo_query "INSERT INTO matomo_site (name, main_url, ts_created, ecommerce, sitesearch, sitesearch_keyword_parameters, sitesearch_category_parameters, timezone, currency, exclude_unknown_urls, excluded_ips, excluded_parameters, excluded_user_agents, excluded_referrers, \`group\`, type, keep_url_fragment, creator_login) VALUES ('Initial Site', 'https://example.com', NOW(), 0, 1, '', '', 'UTC', 'USD', 0, '', '', '', '', '', 'website', 0, 'admin')" 2>/dev/null
fi
SITE_ID=$(matomo_query "SELECT idsite FROM matomo_site WHERE name='Initial Site' LIMIT 1")

# 3. Ensure a default Container exists for this site
# MTM containers are linked to sites. We need one to exist so the agent isn't blocked by "Create Container".
CONTAINER_COUNT=$(matomo_query "SELECT COUNT(*) FROM matomo_tagmanager_container WHERE idsite=$SITE_ID AND deleted=0")
if [ "$CONTAINER_COUNT" -eq "0" ]; then
    echo "Creating default MTM container..."
    # Insert a basic container
    matomo_query "INSERT INTO matomo_tagmanager_container (idsite, name, description, status, created_date, modified_date) VALUES ($SITE_ID, 'Default Container', '', 'active', NOW(), NOW())"
    
    # We also need a default version (Version 1) for a fresh container usually
    CONTAINER_ID=$(matomo_query "SELECT idcontainer FROM matomo_tagmanager_container WHERE idsite=$SITE_ID LIMIT 1")
    
    # Create the initial 'Matomo Configuration' variable which is standard
    # (Skipping deep detail here, just ensuring the UI loads)
fi

# 4. Clean up any existing tags/triggers that might match our target (to prevent false positives)
# We look for json parameters containing our keywords
echo "Cleaning up potential conflicting tags/triggers..."
matomo_query "DELETE FROM matomo_tagmanager_trigger WHERE parameters LIKE '%hero-cta-primary%'" 2>/dev/null || true
matomo_query "DELETE FROM matomo_tagmanager_tag WHERE parameters LIKE '%Hero Click%'" 2>/dev/null || true

# 5. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 6. Launch Browser
echo "Launching Firefox..."
pkill -f firefox 2>/dev/null || true
sleep 2
su - ga -c "DISPLAY=:1 firefox 'http://localhost/' > /tmp/firefox_task.log 2>&1 &"

# Wait for window
wait_for_window "firefox\|mozilla\|Matomo" 60

# Maximize
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="