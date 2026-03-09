#!/bin/bash
# Setup script for Segment + Scheduled Report task
# Occupation: Search Marketing Strategist

echo "=== Setting up Segment Scheduled Report Task ==="
source /workspace/scripts/task_utils.sh

# ── Clean up any pre-existing test artifacts from prior runs ──────────────
echo "Cleaning up pre-existing test segments named 'Mobile Organic Search'..."
matomo_query "DELETE FROM matomo_segment WHERE LOWER(name) LIKE '%mobile organic%' AND login='admin'" 2>/dev/null || true

echo "Cleaning up pre-existing test reports targeting analytics@marketingteam.test..."
matomo_query "DELETE FROM matomo_report WHERE parameters LIKE '%analytics@marketingteam.test%'" 2>/dev/null || true

# ── Ensure at least one website exists (required for reports) ─────────────
echo "Ensuring at least one website exists..."
SITE_COUNT=$(matomo_query "SELECT COUNT(*) FROM matomo_site" 2>/dev/null || echo "0")
if [ "$SITE_COUNT" = "0" ] || [ -z "$SITE_COUNT" ]; then
    echo "No websites found - creating default website..."
    matomo_query "INSERT INTO matomo_site (name, main_url, ts_created, ecommerce, sitesearch, sitesearch_keyword_parameters, sitesearch_category_parameters, timezone, currency, exclude_unknown_urls, excluded_ips, excluded_parameters, excluded_user_agents, excluded_referrers, \`group\`, type, keep_url_fragment, creator_login) VALUES ('Default Site', 'https://example.com', NOW(), 0, 1, '', '', 'UTC', 'USD', 0, '', '', '', '', '', 'website', 0, 'admin')" 2>/dev/null
fi

# ── Record baseline counts ────────────────────────────────────────────────
echo "Recording baseline segment count..."
INITIAL_SEG_COUNT=$(matomo_query "SELECT COUNT(*) FROM matomo_segment WHERE deleted=0" 2>/dev/null || echo "0")
echo "$INITIAL_SEG_COUNT" > /tmp/initial_segment_count
echo "Initial segment count: $INITIAL_SEG_COUNT"

echo "Recording baseline segment IDs..."
matomo_query "SELECT idsegment FROM matomo_segment WHERE deleted=0" 2>/dev/null | tr '\n' ',' | sed 's/,$//' > /tmp/initial_segment_ids
echo "Initial segment IDs: $(cat /tmp/initial_segment_ids)"

echo "Recording baseline report count..."
INITIAL_REP_COUNT=$(matomo_query "SELECT COUNT(*) FROM matomo_report WHERE deleted=0" 2>/dev/null || echo "0")
echo "$INITIAL_REP_COUNT" > /tmp/initial_report_count
echo "Initial report count: $INITIAL_REP_COUNT"

echo "Recording baseline report IDs..."
matomo_query "SELECT idreport FROM matomo_report WHERE deleted=0" 2>/dev/null | tr '\n' ',' | sed 's/,$//' > /tmp/initial_report_ids
echo "Initial report IDs: $(cat /tmp/initial_report_ids)"

# ── Record task start timestamp ───────────────────────────────────────────
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/task_start_timestamp
echo "Task start timestamp: $TASK_START"

# ── Launch Firefox on Matomo ──────────────────────────────────────────────
echo "Starting Firefox on Matomo..."
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
echo "=== Segment Scheduled Report Task Setup Complete ==="
echo ""
echo "TASK: Create a mobile organic search segment + weekly email report"
echo ""
echo "Login credentials: admin / Admin12345"
echo ""
