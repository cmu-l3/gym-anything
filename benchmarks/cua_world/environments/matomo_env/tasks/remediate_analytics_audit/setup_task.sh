#!/bin/bash
# Setup script for Remediate Analytics Audit task
# Seeds a partially broken Matomo configuration that the agent must fix:
#   - FreshCart site with 4 goals (2 correct, 2 deliberately wrong)
#   - 1 segment with a wrong condition
#   - 1 dashboard with 2 wrong widgets
#   - No custom dimension (agent must create one)

echo "=== Setting up Remediate Analytics Audit Task ==="
source /workspace/scripts/task_utils.sh

TARGET_SITE="FreshCart Online Grocery"

# ── Ensure target site exists ─────────────────────────────────────────────
SITE_COUNT=$(matomo_query "SELECT COUNT(*) FROM matomo_site WHERE LOWER(name)=LOWER('$TARGET_SITE')" 2>/dev/null || echo "0")
if [ "$SITE_COUNT" = "0" ] || [ -z "$SITE_COUNT" ]; then
    echo "Creating site '$TARGET_SITE'..."
    matomo_query "INSERT INTO matomo_site (name, main_url, ts_created, ecommerce, sitesearch, sitesearch_keyword_parameters, sitesearch_category_parameters, timezone, currency, exclude_unknown_urls, excluded_ips, excluded_parameters, excluded_user_agents, excluded_referrers, \`group\`, type, keep_url_fragment, creator_login)
                  VALUES ('$TARGET_SITE', 'https://freshcart.example.com', NOW(), 1, 0, '', '', 'America/New_York', 'USD', 0, '', '', '', '', '', 'website', 0, 'admin')" 2>/dev/null
    echo "Site created."
else
    echo "Site '$TARGET_SITE' already exists."
fi

SITE_ID=$(matomo_query "SELECT idsite FROM matomo_site WHERE LOWER(name)=LOWER('$TARGET_SITE') LIMIT 1" 2>/dev/null)
echo "$SITE_ID" > /tmp/freshcart_site_id
echo "FreshCart site ID: $SITE_ID"

# ── Clean pre-existing task artifacts ─────────────────────────────────────
echo "Cleaning pre-existing artifacts for site $SITE_ID..."

# Clean goals
for GOAL_NAME in "Product Page View" "Add to Cart" "Begin Checkout" "Purchase Complete"; do
    matomo_query "DELETE FROM matomo_goal WHERE LOWER(name)=LOWER('$GOAL_NAME') AND idsite=$SITE_ID" 2>/dev/null || true
done

# Clean segments
for SEG_NAME in "Returning Customers" "Mobile Shoppers"; do
    matomo_query "DELETE FROM matomo_segment WHERE LOWER(name)=LOWER('$SEG_NAME') AND enable_only_idsite=$SITE_ID" 2>/dev/null || true
    # Also clean segments with enable_only_idsite=0 that match
    matomo_query "DELETE FROM matomo_segment WHERE LOWER(name)=LOWER('$SEG_NAME') AND login='admin'" 2>/dev/null || true
done

# Clean dashboard
matomo_query "DELETE FROM matomo_user_dashboard WHERE name='Weekly Performance' AND login='admin'" 2>/dev/null || true

# Clean custom dimensions
matomo_query "DELETE FROM matomo_custom_dimensions WHERE LOWER(name)=LOWER('Customer Tier') AND idsite=$SITE_ID" 2>/dev/null || true

echo "Artifacts cleaned."

# ── Seed 4 conversion goals (2 correct, 2 deliberately wrong) ────────────
echo "Seeding conversion goals..."

# Goal 1: Product Page View (CORRECT - agent should NOT touch)
matomo_query "INSERT INTO matomo_goal (idsite, idgoal, name, match_attribute, pattern, pattern_type, case_sensitive, allow_multiple, revenue, deleted)
              VALUES ($SITE_ID, 1, 'Product Page View', 'url', '/products/', 'contains', 0, 0, 0, 0)" 2>/dev/null

# Goal 2: Add to Cart (WRONG pattern: /cart instead of /cart/add)
matomo_query "INSERT INTO matomo_goal (idsite, idgoal, name, match_attribute, pattern, pattern_type, case_sensitive, allow_multiple, revenue, deleted)
              VALUES ($SITE_ID, 2, 'Add to Cart', 'url', '/cart', 'contains', 0, 0, 0, 0)" 2>/dev/null

# Goal 3: Begin Checkout (WRONG type: exact instead of contains)
matomo_query "INSERT INTO matomo_goal (idsite, idgoal, name, match_attribute, pattern, pattern_type, case_sensitive, allow_multiple, revenue, deleted)
              VALUES ($SITE_ID, 3, 'Begin Checkout', 'url', '/checkout', 'exact', 0, 0, 0, 0)" 2>/dev/null

# Goal 4: Purchase Complete (CORRECT - agent should NOT touch)
matomo_query "INSERT INTO matomo_goal (idsite, idgoal, name, match_attribute, pattern, pattern_type, case_sensitive, allow_multiple, revenue, deleted)
              VALUES ($SITE_ID, 4, 'Purchase Complete', 'url', '/order/thank-you', 'exact', 0, 0, 0, 0)" 2>/dev/null

echo "Goals seeded (2 correct, 2 wrong)."

# ── Seed 1 segment with wrong condition ───────────────────────────────────
echo "Seeding broken segment..."

matomo_query "INSERT INTO matomo_segment (name, definition, login, enable_all_users, enable_only_idsite, auto_archive, ts_created, ts_last_edit, deleted)
              VALUES ('Returning Customers', 'visitCount>5', 'admin', 1, $SITE_ID, 1, NOW(), NOW(), 0)" 2>/dev/null

echo "Segment 'Returning Customers' seeded with wrong condition (visitCount>5)."

# ── Seed dashboard with wrong widgets ─────────────────────────────────────
echo "Seeding dashboard with wrong widgets..."

# Use a temp SQL file to avoid shell quoting issues with JSON
cat > /tmp/seed_dashboard.sql << SQLEOF
INSERT INTO matomo_user_dashboard (login, iddashboard, name, layout)
VALUES ('admin', 2, 'Weekly Performance', '[[{"uniqueId":"widgetVisitsSummarygetEvolutionGraph","parameters":{"module":"VisitsSummary","action":"getEvolutionGraph"}}],[{"uniqueId":"widgetReferrersgetReferrerType","parameters":{"module":"Referrers","action":"getReferrerType"}}],[{"uniqueId":"widgetActionsgetPageUrls","parameters":{"module":"Actions","action":"getPageUrls"}},{"uniqueId":"widgetResolutiongetResolution","parameters":{"module":"Resolution","action":"getResolution"}}]]');
SQLEOF
docker cp /tmp/seed_dashboard.sql matomo-db:/tmp/seed_dashboard.sql
docker exec matomo-db bash -c "mysql -u matomo -pmatomo123 matomo < /tmp/seed_dashboard.sql" 2>/dev/null

echo "Dashboard 'Weekly Performance' seeded (VisitsSummary=OK, Referrers=OK, Actions=WRONG, Resolution=WRONG)."

# ── Copy remediation report to agent-accessible location ──────────────────
echo "Placing remediation report..."
mkdir -p /home/ga/Documents
cp /workspace/tasks/remediate_analytics_audit/remediation_report.txt /home/ga/Documents/remediation_report.txt
chown ga:ga /home/ga/Documents/remediation_report.txt
chmod 644 /home/ga/Documents/remediation_report.txt
echo "Report placed at /home/ga/Documents/remediation_report.txt"

# ── Delete stale outputs ──────────────────────────────────────────────────
rm -f /tmp/remediate_analytics_audit_result.json 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# ── Record baseline state ─────────────────────────────────────────────────
echo "Recording baseline state..."

# Record initial goal state (pattern + type for each goal)
matomo_query "SELECT idgoal, name, pattern, pattern_type FROM matomo_goal WHERE idsite=$SITE_ID AND deleted=0 ORDER BY idgoal" > /tmp/initial_goals.txt 2>/dev/null
echo "Initial goals:"
cat /tmp/initial_goals.txt

# Record initial goal IDs (for detecting delete-and-recreate)
matomo_query "SELECT idgoal FROM matomo_goal WHERE idsite=$SITE_ID AND deleted=0 ORDER BY idgoal" 2>/dev/null | tr '\n' ',' | sed 's/,$//' > /tmp/initial_goal_ids.txt
echo "Initial goal IDs: $(cat /tmp/initial_goal_ids.txt)"

# Record initial segment state
matomo_query "SELECT idsegment, name, definition FROM matomo_segment WHERE enable_only_idsite=$SITE_ID AND deleted=0 ORDER BY idsegment" > /tmp/initial_segments.txt 2>/dev/null
echo "Initial segments:"
cat /tmp/initial_segments.txt

INITIAL_SEGMENT_COUNT=$(matomo_query "SELECT COUNT(*) FROM matomo_segment WHERE enable_only_idsite=$SITE_ID AND deleted=0" 2>/dev/null || echo "0")
echo "$INITIAL_SEGMENT_COUNT" > /tmp/initial_segment_count.txt
echo "Initial segment count: $INITIAL_SEGMENT_COUNT"

# Record initial dashboard layout
matomo_query "SELECT layout FROM matomo_user_dashboard WHERE name='Weekly Performance' AND login='admin' LIMIT 1" > /tmp/initial_dashboard_layout.txt 2>/dev/null
echo "Initial dashboard layout recorded."

# Record initial custom dimension count
INITIAL_DIM_COUNT=$(matomo_query "SELECT COUNT(*) FROM matomo_custom_dimensions WHERE idsite=$SITE_ID" 2>/dev/null || echo "0")
echo "$INITIAL_DIM_COUNT" > /tmp/initial_dimension_count.txt
echo "Initial custom dimension count: $INITIAL_DIM_COUNT"

# ── Task start timestamp ──────────────────────────────────────────────────
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/task_start_timestamp
echo "Task start timestamp: $TASK_START"

# ── Launch Firefox ────────────────────────────────────────────────────────
pkill -f firefox 2>/dev/null || true
sleep 2

echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority firefox 'http://localhost/index.php?module=CoreHome&action=index&idSite=$SITE_ID&period=day&date=today' > /tmp/firefox_task.log 2>&1 &"
sleep 5

if ! wait_for_window "firefox\|mozilla\|Matomo" 30; then
    echo "WARNING: Firefox window not detected"
fi

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape 2>/dev/null || true
take_screenshot /tmp/task_initial_screenshot.png

echo ""
echo "=== Remediate Analytics Audit Task Setup Complete ==="
echo ""
echo "TASK: Read /home/ga/Documents/remediation_report.txt and fix all issues."
echo "  - Fix 2 broken conversion goals (Add to Cart, Begin Checkout)"
echo "  - Fix 1 broken segment (Returning Customers)"
echo "  - Create 1 missing segment (Mobile Shoppers)"
echo "  - Replace 2 wrong dashboard widgets"
echo "  - Create 1 missing custom dimension (Customer Tier)"
echo ""
echo "Login credentials: admin / Admin12345"
echo "Target site: FreshCart Online Grocery (ID: $SITE_ID)"
echo ""
