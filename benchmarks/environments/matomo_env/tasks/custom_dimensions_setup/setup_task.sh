#!/bin/bash
# Setup script for Custom Dimensions Setup task
# Occupation: Market Research Analyst
# Seeds the Research Platform site; cleans any prior test dimensions.

echo "=== Setting up Custom Dimensions Setup Task ==="
source /workspace/scripts/task_utils.sh

TARGET_SITE="Research Platform"

# ── Ensure target site exists ─────────────────────────────────────────────
SITE_COUNT=$(matomo_query "SELECT COUNT(*) FROM matomo_site WHERE LOWER(name)=LOWER('$TARGET_SITE')" 2>/dev/null || echo "0")
if [ "$SITE_COUNT" = "0" ] || [ -z "$SITE_COUNT" ]; then
    echo "Creating site '$TARGET_SITE'..."
    matomo_query "INSERT INTO matomo_site (name, main_url, ts_created, ecommerce, sitesearch, sitesearch_keyword_parameters, sitesearch_category_parameters, timezone, currency, exclude_unknown_urls, excluded_ips, excluded_parameters, excluded_user_agents, excluded_referrers, \`group\`, type, keep_url_fragment, creator_login)
                  VALUES ('$TARGET_SITE', 'https://research-platform.example.com', NOW(), 0, 0, '', '', 'UTC', 'USD', 0, '', '', '', '', '', 'website', 0, 'admin')" 2>/dev/null
    echo "Site created."
else
    echo "Site '$TARGET_SITE' already exists."
fi

SITE_ID=$(matomo_query "SELECT idsite FROM matomo_site WHERE LOWER(name)=LOWER('$TARGET_SITE') LIMIT 1" 2>/dev/null)
echo "$SITE_ID" > /tmp/research_platform_site_id
echo "Research Platform site ID: $SITE_ID"

# ── Clean any pre-existing test dimensions for this site ──────────────────
if [ -n "$SITE_ID" ]; then
    for DIM_NAME in "Subscription Tier" "User Cohort" "Traffic Source Detail" "Page Category" "Form Interaction"; do
        COUNT=$(matomo_query "SELECT COUNT(*) FROM matomo_custom_dimension WHERE LOWER(name)=LOWER('$DIM_NAME') AND idsite=$SITE_ID" 2>/dev/null || echo "0")
        if [ "$COUNT" != "0" ] && [ -n "$COUNT" ]; then
            echo "Removing pre-existing dimension '$DIM_NAME' for site $SITE_ID..."
            matomo_query "DELETE FROM matomo_custom_dimension WHERE LOWER(name)=LOWER('$DIM_NAME') AND idsite=$SITE_ID" 2>/dev/null || true
        fi
    done
fi

# ── Record baseline ───────────────────────────────────────────────────────
INITIAL_DIM_COUNT="0"
if [ -n "$SITE_ID" ]; then
    INITIAL_DIM_COUNT=$(matomo_query "SELECT COUNT(*) FROM matomo_custom_dimension WHERE idsite=$SITE_ID" 2>/dev/null || echo "0")
fi
echo "$INITIAL_DIM_COUNT" > /tmp/initial_dimension_count
echo "Initial custom dimension count for site $SITE_ID: $INITIAL_DIM_COUNT"

# Record existing dimension IDs
if [ -n "$SITE_ID" ]; then
    matomo_query "SELECT idcustomdimension FROM matomo_custom_dimension WHERE idsite=$SITE_ID" 2>/dev/null | tr '\n' ',' | sed 's/,$//' > /tmp/initial_dimension_ids
else
    echo "" > /tmp/initial_dimension_ids
fi
echo "Initial dimension IDs: $(cat /tmp/initial_dimension_ids)"

# ── Task start timestamp ──────────────────────────────────────────────────
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/task_start_timestamp
echo "Task start timestamp: $TASK_START"

# ── Launch Firefox ────────────────────────────────────────────────────────
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
echo "=== Custom Dimensions Setup Task Setup Complete ==="
echo ""
echo "TASK: Create 5 custom dimensions (3 visit-scope + 2 action-scope) for 'Research Platform'."
echo ""
echo "Login credentials: admin / Admin12345"
echo ""
