#!/bin/bash
# Setup script for View Visitors Dashboard task

echo "=== Setting up View Visitors Dashboard Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Ensure Matomo is installed and has at least one website
echo "Checking Matomo installation status..."
if ! matomo_is_installed; then
    echo "ERROR: Matomo installation wizard is still showing"
    echo "Please complete the Matomo installation first"
fi

# Ensure at least one website exists
echo "Checking for existing websites..."
SITE_COUNT=$(matomo_query "SELECT COUNT(*) FROM matomo_site" 2>/dev/null || echo "0")

if [ "$SITE_COUNT" = "0" ] || [ -z "$SITE_COUNT" ]; then
    echo "No websites found - creating default website..."
    matomo_query "INSERT INTO matomo_site (name, main_url, ts_created, ecommerce, sitesearch, sitesearch_keyword_parameters, sitesearch_category_parameters, timezone, currency, exclude_unknown_urls, excluded_ips, excluded_parameters, excluded_user_agents, \`group\`, type, keep_url_fragment, creator_login)
                  VALUES ('Demo Website', 'https://demo.example.com', NOW(), 0, 1, '', '', 'UTC', 'USD', 0, '', '', '', '', 'website', 0, 'admin')" 2>/dev/null
    echo "Default website created"
fi

# Populate synthetic visitor data so dashboard has something to display
echo "Populating synthetic visitor data..."
if [ -x /workspace/scripts/populate_visitor_data.sh ]; then
    /workspace/scripts/populate_visitor_data.sh || echo "Warning: Visitor data population encountered errors"
else
    echo "Warning: populate_visitor_data.sh not found or not executable"
fi

# Record task start timestamp
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/task_start_timestamp
echo "Task start timestamp: $TASK_START ($(date -d @$TASK_START))"

# Record initial page state (will check if visitors overview is loaded at end)
echo "initial" > /tmp/initial_page_state

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
echo "=== View Visitors Dashboard Task Setup Complete ==="
echo ""
echo "TASK: Navigate to the Visitors Overview dashboard and change the date range to 'Last 30 days'"
echo ""
echo "Steps:"
echo "  1. Log in to Matomo (admin / Admin12345)"
echo "  2. Click on 'Visitors' in the left menu"
echo "  3. Select 'Overview' from the submenu"
echo "  4. Click on the date range selector (top right)"
echo "  5. Select 'Last 30 days'"
echo "  6. Verify the dashboard updates"
echo ""
