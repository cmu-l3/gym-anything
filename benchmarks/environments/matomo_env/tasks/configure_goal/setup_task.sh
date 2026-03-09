#!/bin/bash
# Setup script for Configure Goal task

echo "=== Setting up Configure Goal Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Expected goal details
EXPECTED_GOAL_NAME="Newsletter Signup"

# Clean up any pre-existing test goal (for re-runs)
echo "Checking for pre-existing test goal..."
EXISTING_GOAL=$(matomo_query "SELECT idgoal FROM matomo_goal WHERE LOWER(name)=LOWER('$EXPECTED_GOAL_NAME')" 2>/dev/null)

if [ -n "$EXISTING_GOAL" ]; then
    echo "Found existing goal with idgoal=$EXISTING_GOAL, removing for clean test..."
    matomo_query "DELETE FROM matomo_goal WHERE LOWER(name)=LOWER('$EXPECTED_GOAL_NAME')" 2>/dev/null || true
    echo "Existing test goal removed"
fi

# Ensure at least one website exists (goal requires a site)
echo "Ensuring a website exists for goal configuration..."
SITE_COUNT=$(matomo_query "SELECT COUNT(*) FROM matomo_site" 2>/dev/null || echo "0")

if [ "$SITE_COUNT" = "0" ] || [ -z "$SITE_COUNT" ]; then
    echo "No websites found - creating default website for goal tracking..."
    matomo_query "INSERT INTO matomo_site (name, main_url, ts_created, ecommerce, sitesearch, sitesearch_keyword_parameters, sitesearch_category_parameters, timezone, currency, exclude_unknown_urls, excluded_ips, excluded_parameters, excluded_user_agents, \`group\`, type, keep_url_fragment, creator_login)
                  VALUES ('Default Website', 'https://example.com', NOW(), 0, 1, '', '', 'UTC', 'USD', 0, '', '', '', '', 'website', 0, 'admin')" 2>/dev/null
    echo "Default website created"
fi

# Record initial goal count for verification
echo "Recording initial goal count..."
INITIAL_COUNT=$(matomo_query "SELECT COUNT(*) FROM matomo_goal" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_goal_count
echo "Initial goal count: $INITIAL_COUNT"

# Record existing goal IDs for anti-gaming (detect renamed goals)
echo "Recording existing goal IDs for anti-gaming..."
matomo_query "SELECT idgoal FROM matomo_goal WHERE deleted=0" 2>/dev/null | tr '\n' ',' | sed 's/,$//' > /tmp/initial_goal_ids
INITIAL_IDS=$(cat /tmp/initial_goal_ids 2>/dev/null || echo "")
echo "Initial goal IDs: $INITIAL_IDS"

# Record task start timestamp (critical for anti-gaming)
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/task_start_timestamp
echo "Task start timestamp: $TASK_START ($(date -d @$TASK_START))"

# Ensure Firefox is running on Matomo
echo "Ensuring Firefox is running..."
MATOMO_URL="http://localhost/"

# Kill any existing Firefox instances for clean start
pkill -f firefox 2>/dev/null || true
sleep 2

echo "Starting Firefox..."
su - ga -c "DISPLAY=:1 firefox '$MATOMO_URL' > /tmp/firefox_task.log 2>&1 &"
sleep 5

# Wait for Firefox window
if ! wait_for_window "firefox\|mozilla\|Matomo" 30; then
    echo "WARNING: Firefox window not detected"
fi

# Focus and maximize Firefox window
echo "Focusing Firefox window..."
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Dismiss any Firefox first-run dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5

# Take initial screenshot for audit
take_screenshot /tmp/task_initial_screenshot.png
echo "Initial screenshot saved to /tmp/task_initial_screenshot.png"

# Copy initial screenshot to artifacts for persistence
if [ -n "$ARTIFACTS_DIR" ] && [ -d "$ARTIFACTS_DIR" ]; then
    cp /tmp/task_initial_screenshot.png "$ARTIFACTS_DIR/initial_screenshot.png" 2>/dev/null || true
    echo "Initial screenshot copied to artifacts: $ARTIFACTS_DIR/initial_screenshot.png"
elif [ -d "/workspace/artifacts" ]; then
    cp /tmp/task_initial_screenshot.png "/workspace/artifacts/initial_screenshot.png" 2>/dev/null || true
    echo "Initial screenshot copied to /workspace/artifacts/"
fi

echo ""
echo "=== Configure Goal Task Setup Complete ==="
echo ""
echo "TASK: Configure a conversion goal in Matomo with the following details:"
echo ""
echo "  Goal Name:      Newsletter Signup"
echo "  Trigger:        Visit a given URL (destination)"
echo "  Pattern Type:   Contains"
echo "  URL Pattern:    /newsletter/thank-you"
echo "  Revenue:        5.00 USD per conversion"
echo ""
echo "Login credentials: admin / Admin12345"
echo ""
echo "Navigate to: Administration > Goals > Manage Goals > Add a new Goal"
echo ""
