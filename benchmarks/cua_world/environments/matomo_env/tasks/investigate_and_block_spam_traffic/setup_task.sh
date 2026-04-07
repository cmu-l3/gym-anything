#!/bin/bash
# Setup script for "Investigate and Block Spam Traffic"
# Injects spam records into the database and ensures UI is ready.

set -e
echo "=== Setting up Spam Investigation Task ==="
source /workspace/scripts/task_utils.sh

# 1. Ensure Matomo is running and Initial Site exists
# ---------------------------------------------------
echo "Checking Matomo status..."
if ! matomo_is_installed; then
    echo "ERROR: Matomo not fully installed. Please complete installation first."
    # Try to trigger the setup script again or fail
    exit 1
fi

# Ensure Initial Site exists
SITE_ID=$(matomo_query "SELECT idsite FROM matomo_site WHERE idsite=1" 2>/dev/null || echo "")
if [ -z "$SITE_ID" ]; then
    echo "Creating Initial Site..."
    matomo_query "INSERT INTO matomo_site (idsite, name, main_url, ts_created, ecommerce, sitesearch, timezone, currency, type) VALUES (1, 'Initial Site', 'https://initial-site.example.com', NOW(), 0, 1, 'UTC', 'USD', 'website')"
fi

# 2. Reset Exclusions (Clean Slate)
# ---------------------------------------------------
echo "Clearing existing exclusions..."
matomo_query "UPDATE matomo_site SET excluded_ips='', excluded_user_agents='', excluded_referrers='' WHERE idsite=1"

# 3. Inject Spam Data
# ---------------------------------------------------
echo "Injecting spam traffic data..."

# Constants for spam pattern
SPAM_IP="192.0.2.105"
SPAM_UA="TrafficBotPro/3.0"
SPAM_REF="http://traffic-bot-pro.test/free-traffic"
SAFE_UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"

# We need to insert directly into matomo_log_visit
# location_ip is varbinary(16). We use INET6_ATON for generic IP support in MariaDB/MySQL.

# Generate 40 spam visits spread over the last 12 hours
docker exec matomo-db mysql -u matomo -pmatomo123 matomo -e "
INSERT INTO matomo_log_visit (
    idsite, idvisitor, visit_first_action_time, visit_last_action_time,
    location_ip, config_browser_name, config_browser_version,
    referer_type, referer_url, visitor_returning, visitor_count_visits
)
SELECT 
    1, 
    UNHEX(MD5(UUID())), 
    DATE_SUB(NOW(), INTERVAL (seq * 15) MINUTE), 
    DATE_SUB(NOW(), INTERVAL (seq * 15) MINUTE), 
    INET6_ATON('$SPAM_IP'), 
    'Bot', 
    '3.0', 
    2, 
    '$SPAM_REF', 
    1, 
    seq
FROM (
    SELECT a.N + b.N * 10 + 1 as seq
    FROM 
    (SELECT 0 AS N UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) a,
    (SELECT 0 AS N UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3) b
    ORDER BY seq
    LIMIT 40
) sequence;
"

# Inject 5 legitimate visits (Noise)
docker exec matomo-db mysql -u matomo -pmatomo123 matomo -e "
INSERT INTO matomo_log_visit (
    idsite, idvisitor, visit_first_action_time, visit_last_action_time,
    location_ip, config_browser_name, config_browser_version,
    referer_type, referer_url
) VALUES
(1, UNHEX(MD5('safe1')), NOW(), NOW(), INET6_ATON('127.0.0.1'), 'Chrome', '91.0', 1, 'https://www.google.com'),
(1, UNHEX(MD5('safe2')), DATE_SUB(NOW(), INTERVAL 1 HOUR), DATE_SUB(NOW(), INTERVAL 1 HOUR), INET6_ATON('10.0.0.5'), 'Firefox', '89.0', 1, 'https://bing.com');
"

echo "Data injection complete."

# 4. Prepare Browser
# ---------------------------------------------------
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/task_start_timestamp

# Kill any existing Firefox
pkill -f firefox 2>/dev/null || true
sleep 2

# Start Firefox on Visitors Dashboard
echo "Starting Firefox..."
su - ga -c "DISPLAY=:1 firefox 'http://localhost/index.php?module=CoreHome&action=index&idSite=1&period=day&date=today#?idSite=1&period=day&date=today&category=General_Visitors&subcategory=General_VisitorLog' > /tmp/firefox.log 2>&1 &"

# Wait for window
wait_for_window "firefox\|Matomo" 60

# Maximize
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Setup Complete ==="