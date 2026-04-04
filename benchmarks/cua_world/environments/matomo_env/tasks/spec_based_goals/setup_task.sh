#!/bin/bash
# Setup script for Spec-Based Goals task
# Occupation: Online Merchant
# Seeds the SportsFit Shop site; cleans any prior goals.

echo "=== Setting up Spec-Based Goals Task ==="
source /workspace/scripts/task_utils.sh

TARGET_SITE="SportsFit Shop"

# ── Ensure target site exists ─────────────────────────────────────────────
SITE_COUNT=$(matomo_query "SELECT COUNT(*) FROM matomo_site WHERE LOWER(name)=LOWER('$TARGET_SITE')" 2>/dev/null || echo "0")
if [ "$SITE_COUNT" = "0" ] || [ -z "$SITE_COUNT" ]; then
    echo "Creating site '$TARGET_SITE'..."
    matomo_query "INSERT INTO matomo_site (name, main_url, ts_created, ecommerce, sitesearch, sitesearch_keyword_parameters, sitesearch_category_parameters, timezone, currency, exclude_unknown_urls, excluded_ips, excluded_parameters, excluded_user_agents, excluded_referrers, \`group\`, type, keep_url_fragment, creator_login)
                  VALUES ('$TARGET_SITE', 'https://sportsfit-shop.example.com', NOW(), 1, 0, '', '', 'UTC', 'USD', 0, '', '', '', '', '', 'website', 0, 'admin')" 2>/dev/null
    echo "Site created."
else
    echo "Site '$TARGET_SITE' already exists."
fi

SITE_ID=$(matomo_query "SELECT idsite FROM matomo_site WHERE LOWER(name)=LOWER('$TARGET_SITE') LIMIT 1" 2>/dev/null)
echo "$SITE_ID" > /tmp/sportsfit_site_id
echo "SportsFit Shop site ID: $SITE_ID"

# ── Remove any pre-existing funnel goals from prior runs ──────────────────
if [ -n "$SITE_ID" ]; then
    for GOAL_NAME in "Product Page View" "Add to Cart" "Checkout Started" "Purchase Confirmation"; do
        COUNT=$(matomo_query "SELECT COUNT(*) FROM matomo_goal WHERE LOWER(name)=LOWER('$GOAL_NAME') AND idsite=$SITE_ID AND deleted=0" 2>/dev/null || echo "0")
        if [ "$COUNT" != "0" ] && [ -n "$COUNT" ]; then
            echo "Removing pre-existing goal '$GOAL_NAME' for site $SITE_ID..."
            matomo_query "UPDATE matomo_goal SET deleted=1 WHERE LOWER(name)=LOWER('$GOAL_NAME') AND idsite=$SITE_ID" 2>/dev/null || true
        fi
    done
fi

# ── Record baseline goal counts ───────────────────────────────────────────
INITIAL_GOAL_COUNT="0"
[ -n "$SITE_ID" ] && INITIAL_GOAL_COUNT=$(matomo_query "SELECT COUNT(*) FROM matomo_goal WHERE idsite=$SITE_ID AND deleted=0" 2>/dev/null || echo "0")
echo "$INITIAL_GOAL_COUNT" > /tmp/initial_goal_count_sportsfit
echo "Initial goal count for site $SITE_ID: $INITIAL_GOAL_COUNT"

# Record existing goal IDs
if [ -n "$SITE_ID" ]; then
    matomo_query "SELECT idgoal FROM matomo_goal WHERE idsite=$SITE_ID AND deleted=0" 2>/dev/null | tr '\n' ',' | sed 's/,$//' > /tmp/initial_goal_ids_sportsfit
else
    echo "" > /tmp/initial_goal_ids_sportsfit
fi
echo "Initial goal IDs: $(cat /tmp/initial_goal_ids_sportsfit)"

# ── Task start timestamp ──────────────────────────────────────────────────
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/task_start_timestamp
echo "Task start timestamp: $TASK_START"

# ── Verify spec file is accessible ───────────────────────────────────────
SPEC_FILE="/workspace/tasks/spec_based_goals/funnel_spec.txt"
if [ -f "$SPEC_FILE" ]; then
    echo "Specification file found at $SPEC_FILE"
    echo "File size: $(wc -l < "$SPEC_FILE") lines"
else
    echo "WARNING: Specification file not found at $SPEC_FILE"
fi

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
echo "=== Spec-Based Goals Task Setup Complete ==="
echo ""
echo "TASK: Read funnel_spec.txt and create 4 conversion goals for 'SportsFit Shop'."
echo "Spec file location: /workspace/tasks/spec_based_goals/funnel_spec.txt"
echo ""
echo "Login credentials: admin / Admin12345"
echo ""
