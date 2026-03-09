#!/bin/bash
# Setup script for Analyst User Access task
# Occupation: Marketing Manager
# Seeds 4 sites; removes any prior test user.

echo "=== Setting up Analyst User Access Task ==="
source /workspace/scripts/task_utils.sh

TARGET_LOGIN="jamie.rodriguez"

# ── Remove any pre-existing test user from prior runs ────────────────────
echo "Removing any pre-existing test user '$TARGET_LOGIN'..."
matomo_query "DELETE FROM matomo_access WHERE login='$TARGET_LOGIN'" 2>/dev/null || true
matomo_query "DELETE FROM matomo_report WHERE login='$TARGET_LOGIN'" 2>/dev/null || true
matomo_query "DELETE FROM matomo_user WHERE login='$TARGET_LOGIN'" 2>/dev/null || true

# ── Seed the 4 required sites ─────────────────────────────────────────────
for SITE_NAME in "Main Store" "Blog" "Mobile App" "Confidential Data"; do
    EXISTING=$(matomo_query "SELECT COUNT(*) FROM matomo_site WHERE LOWER(name)=LOWER('$SITE_NAME')" 2>/dev/null || echo "0")
    if [ "$EXISTING" = "0" ] || [ -z "$EXISTING" ]; then
        echo "Creating site: $SITE_NAME"
        SAFE_URL=$(echo "$SITE_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
        matomo_query "INSERT INTO matomo_site (name, main_url, ts_created, ecommerce, sitesearch, sitesearch_keyword_parameters, sitesearch_category_parameters, timezone, currency, exclude_unknown_urls, excluded_ips, excluded_parameters, excluded_user_agents, excluded_referrers, \`group\`, type, keep_url_fragment, creator_login)
                      VALUES ('$SITE_NAME', 'https://${SAFE_URL}.example.com', NOW(), 0, 0, '', '', 'UTC', 'USD', 0, '', '', '', '', '', 'website', 0, 'admin')" 2>/dev/null
    else
        echo "Site '$SITE_NAME' already exists"
    fi
done

# ── Record site IDs ───────────────────────────────────────────────────────
MAIN_STORE_ID=$(matomo_query "SELECT idsite FROM matomo_site WHERE LOWER(name)=LOWER('Main Store') LIMIT 1" 2>/dev/null)
BLOG_ID=$(matomo_query "SELECT idsite FROM matomo_site WHERE LOWER(name)=LOWER('Blog') LIMIT 1" 2>/dev/null)
MOBILE_APP_ID=$(matomo_query "SELECT idsite FROM matomo_site WHERE LOWER(name)=LOWER('Mobile App') LIMIT 1" 2>/dev/null)
CONFIDENTIAL_ID=$(matomo_query "SELECT idsite FROM matomo_site WHERE LOWER(name)=LOWER('Confidential Data') LIMIT 1" 2>/dev/null)

echo "$MAIN_STORE_ID" > /tmp/analyst_main_store_id
echo "$BLOG_ID" > /tmp/analyst_blog_id
echo "$MOBILE_APP_ID" > /tmp/analyst_mobile_app_id
echo "$CONFIDENTIAL_ID" > /tmp/analyst_confidential_id

echo "Site IDs: MainStore=$MAIN_STORE_ID Blog=$BLOG_ID MobileApp=$MOBILE_APP_ID Confidential=$CONFIDENTIAL_ID"

# ── Verify sites ──────────────────────────────────────────────────────────
matomo_query_verbose "SELECT idsite, name FROM matomo_site WHERE name IN ('Main Store','Blog','Mobile App','Confidential Data')" 2>/dev/null

# ── Record baselines ──────────────────────────────────────────────────────
INITIAL_USER_COUNT=$(matomo_query "SELECT COUNT(*) FROM matomo_user WHERE superuser_access=0" 2>/dev/null || echo "0")
echo "$INITIAL_USER_COUNT" > /tmp/initial_user_count
echo "Initial non-superuser count: $INITIAL_USER_COUNT"

INITIAL_USER_IDS=$(matomo_query "SELECT login FROM matomo_user" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
echo "$INITIAL_USER_IDS" > /tmp/initial_user_ids
echo "Initial user logins: $INITIAL_USER_IDS"

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
echo "=== Analyst User Access Task Setup Complete ==="
echo ""
echo "TASK: Create user jamie.rodriguez with selective site access + monthly report."
echo ""
echo "Login credentials: admin / Admin12345"
echo ""
