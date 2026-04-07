#!/bin/bash
# Setup script for Create Campaign Annotations task

echo "=== Setting up Create Campaign Annotations Task ==="
source /workspace/scripts/task_utils.sh

# 1. Ensure 'Initial Site' (ID 1) exists
echo "Checking for Initial Site..."
SITE_COUNT=$(matomo_query "SELECT COUNT(*) FROM matomo_site WHERE idsite=1" 2>/dev/null || echo "0")
if [ "$SITE_COUNT" = "0" ]; then
    echo "Creating Initial Site..."
    matomo_query "INSERT INTO matomo_site (idsite, name, main_url, ts_created, ecommerce, sitesearch, sitesearch_keyword_parameters, sitesearch_category_parameters, timezone, currency, exclude_unknown_urls, excluded_ips, excluded_parameters, excluded_user_agents, \`group\`, type, keep_url_fragment, creator_login)
                  VALUES (1, 'Initial Site', '2024-01-01 00:00:00', 0, 1, '', '', 'UTC', 'USD', 0, '', '', '', '', '', 'website', 0, 'admin')" 2>/dev/null
fi

# 2. Ensure matomo_annotation table exists
echo "Ensuring annotation table exists..."
matomo_query "CREATE TABLE IF NOT EXISTS matomo_annotation (
    idannotation INT UNSIGNED NOT NULL AUTO_INCREMENT,
    idsite INT UNSIGNED NOT NULL,
    date DATE NOT NULL,
    note TEXT NOT NULL,
    login VARCHAR(100) NULL,
    starred TINYINT NOT NULL DEFAULT 0,
    PRIMARY KEY (idannotation, idsite)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;" 2>/dev/null || true

# 3. Clean up any existing annotations on Site 1 to start fresh
echo "Cleaning up old annotations..."
matomo_query "DELETE FROM matomo_annotation WHERE idsite=1" 2>/dev/null || true

# 4. Populate dummy historical data for March/April 2025
# (So the graph isn't empty when the agent navigates there)
echo "Populating historical data for target dates..."
# Insert a few visits for the target dates so the graph renders points
for DATE in "2025-03-17" "2025-04-01" "2025-04-14"; do
    matomo_query "INSERT INTO matomo_log_visit (
        idsite, visit_first_action_time, visit_last_action_time,
        visit_total_actions, visit_total_time, visitor_returning, visitor_count_visits,
        location_country, config_browser_name, referer_type
    ) VALUES (
        1, '${DATE} 10:00:00', '${DATE} 10:05:00',
        3, 300, 1, 5, 'US', 'CH', 1
    );" 2>/dev/null || true
done
# Trigger archive processing for these dates (simplistic trigger)
docker exec matomo php /var/www/html/console core:archive --force-all-websites --force-date-last-n=1000 > /dev/null 2>&1 &

# 5. Record baseline state
INITIAL_COUNT=$(matomo_query "SELECT COUNT(*) FROM matomo_annotation WHERE idsite=1" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_annotation_count
echo "Initial annotation count: $INITIAL_COUNT"

TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/task_start_timestamp

# 6. Launch Firefox
echo "Starting Firefox..."
# We deliberately start at the dashboard (current date) so agent must navigate to 2025
MATOMO_URL="http://localhost/index.php?module=CoreHome&action=index&idSite=1&period=day&date=today"

pkill -f firefox 2>/dev/null || true
sleep 2
su - ga -c "DISPLAY=:1 firefox '$MATOMO_URL' > /tmp/firefox_task.log 2>&1 &"
sleep 5

# 7. Finalize setup
wait_for_window "firefox\|mozilla\|Matomo" 30
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

take_screenshot /tmp/task_initial_screenshot.png
echo "=== Setup Complete ==="