#!/bin/bash
# Setup script for Fix Regional Sites task
# Occupation: Online Merchant
# Seeds three regional sites with deliberately wrong configurations.

echo "=== Setting up Fix Regional Sites Task ==="
source /workspace/scripts/task_utils.sh

# ── Remove any prior seeded sites from previous runs ─────────────────────
echo "Removing any pre-existing seeded regional sites..."
for SITE_NAME in "UK Fashion Store" "German Auto Parts" "Tokyo Electronics"; do
    matomo_query "DELETE FROM matomo_site WHERE LOWER(name)=LOWER('$SITE_NAME')" 2>/dev/null || true
done

# ── Ensure 'Initial Site' exists (sanity check) ───────────────────────────
CTRL_COUNT=$(matomo_query "SELECT COUNT(*) FROM matomo_site WHERE LOWER(name)=LOWER('Initial Site')" 2>/dev/null || echo "0")
if [ "$CTRL_COUNT" = "0" ] || [ -z "$CTRL_COUNT" ]; then
    echo "Creating Initial Site as control..."
    matomo_query "INSERT INTO matomo_site (name, main_url, ts_created, ecommerce, sitesearch, sitesearch_keyword_parameters, sitesearch_category_parameters, timezone, currency, exclude_unknown_urls, excluded_ips, excluded_parameters, excluded_user_agents, excluded_referrers, \`group\`, type, keep_url_fragment, creator_login)
                  VALUES ('Initial Site', 'https://example.com', NOW(), 0, 1, '', '', 'UTC', 'USD', 0, '', '', '', '', '', 'website', 0, 'admin')" 2>/dev/null
fi

# ── Record Initial Site baseline (for wrong-target gate) ─────────────────
echo "Recording Initial Site baseline..."
INIT_SITE_DATA=$(matomo_query "SELECT idsite, currency, timezone, ecommerce FROM matomo_site WHERE LOWER(name)=LOWER('Initial Site') LIMIT 1" 2>/dev/null)
echo "$INIT_SITE_DATA" > /tmp/initial_site_baseline
echo "Initial Site baseline: $INIT_SITE_DATA"

# ── Seed the three broken regional sites ─────────────────────────────────
echo "Seeding 'UK Fashion Store' with wrong config (USD, America/New_York, ecommerce=0)..."
matomo_query "INSERT INTO matomo_site (name, main_url, ts_created, ecommerce, sitesearch, sitesearch_keyword_parameters, sitesearch_category_parameters, timezone, currency, exclude_unknown_urls, excluded_ips, excluded_parameters, excluded_user_agents, excluded_referrers, \`group\`, type, keep_url_fragment, creator_login)
              VALUES ('UK Fashion Store', 'https://ukfashion.example.com', NOW(), 0, 0, '', '', 'America/New_York', 'USD', 0, '', '', '', '', '', 'website', 0, 'admin')" 2>/dev/null

echo "Seeding 'German Auto Parts' with wrong config (USD, America/New_York, ecommerce=0)..."
matomo_query "INSERT INTO matomo_site (name, main_url, ts_created, ecommerce, sitesearch, sitesearch_keyword_parameters, sitesearch_category_parameters, timezone, currency, exclude_unknown_urls, excluded_ips, excluded_parameters, excluded_user_agents, excluded_referrers, \`group\`, type, keep_url_fragment, creator_login)
              VALUES ('German Auto Parts', 'https://germanautoparts.example.com', NOW(), 0, 0, '', '', 'America/New_York', 'USD', 0, '', '', '', '', '', 'website', 0, 'admin')" 2>/dev/null

echo "Seeding 'Tokyo Electronics' with wrong config (USD, America/New_York, ecommerce=0)..."
matomo_query "INSERT INTO matomo_site (name, main_url, ts_created, ecommerce, sitesearch, sitesearch_keyword_parameters, sitesearch_category_parameters, timezone, currency, exclude_unknown_urls, excluded_ips, excluded_parameters, excluded_user_agents, excluded_referrers, \`group\`, type, keep_url_fragment, creator_login)
              VALUES ('Tokyo Electronics', 'https://tokyoelectronics.example.com', NOW(), 0, 0, '', '', 'America/New_York', 'USD', 0, '', '', '', '', '', 'website', 0, 'admin')" 2>/dev/null

# ── Verify sites were created ─────────────────────────────────────────────
echo "Verifying seeded sites..."
matomo_query_verbose "SELECT idsite, name, currency, timezone, ecommerce FROM matomo_site WHERE name IN ('UK Fashion Store','German Auto Parts','Tokyo Electronics')" 2>/dev/null

# ── Record site IDs ───────────────────────────────────────────────────────
UK_ID=$(matomo_query "SELECT idsite FROM matomo_site WHERE LOWER(name)=LOWER('UK Fashion Store') LIMIT 1" 2>/dev/null)
DE_ID=$(matomo_query "SELECT idsite FROM matomo_site WHERE LOWER(name)=LOWER('German Auto Parts') LIMIT 1" 2>/dev/null)
JP_ID=$(matomo_query "SELECT idsite FROM matomo_site WHERE LOWER(name)=LOWER('Tokyo Electronics') LIMIT 1" 2>/dev/null)
echo "$UK_ID" > /tmp/regional_uk_site_id
echo "$DE_ID" > /tmp/regional_de_site_id
echo "$JP_ID" > /tmp/regional_jp_site_id
echo "Site IDs: UK=$UK_ID DE=$DE_ID JP=$JP_ID"

# ── Record task start timestamp ───────────────────────────────────────────
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/task_start_timestamp
echo "Task start timestamp: $TASK_START"

# ── Start Firefox ─────────────────────────────────────────────────────────
pkill -f firefox 2>/dev/null || true
sleep 2
su - ga -c "DISPLAY=:1 firefox 'http://localhost/' > /tmp/firefox_task.log 2>&1 &"
sleep 5
if ! wait_for_window "firefox\|mozilla\|Matomo" 30; then
    echo "WARNING: Firefox window not detected"
fi
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
take_screenshot /tmp/task_initial_screenshot.png

echo ""
echo "=== Fix Regional Sites Task Setup Complete ==="
echo ""
echo "TASK: Fix currency, timezone, and ecommerce for 3 regional sites."
echo "DO NOT modify 'Initial Site'."
echo ""
echo "Login credentials: admin / Admin12345"
echo ""
