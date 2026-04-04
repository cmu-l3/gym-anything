#!/bin/bash
# Setup script for Add Website task

echo "=== Setting up Add Website Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Expected website details
EXPECTED_SITE_NAME="TechBlog Demo"
EXPECTED_SITE_URL="https://techblog-demo.example.com"

# Clean up any pre-existing test website (for re-runs)
echo "Checking for pre-existing test website..."
EXISTING_SITE=$(matomo_query "SELECT idsite FROM matomo_site WHERE LOWER(name)=LOWER('$EXPECTED_SITE_NAME')" 2>/dev/null)

if [ -n "$EXISTING_SITE" ]; then
    echo "Found existing site with idsite=$EXISTING_SITE, removing for clean test..."
    # Delete related records first (foreign key constraints)
    matomo_query "DELETE FROM matomo_site_url WHERE idsite=$EXISTING_SITE" 2>/dev/null || true
    matomo_query "DELETE FROM matomo_goal WHERE idsite=$EXISTING_SITE" 2>/dev/null || true
    matomo_query "DELETE FROM matomo_site WHERE idsite=$EXISTING_SITE" 2>/dev/null || true
    echo "Existing test website removed"
fi

# Record initial site count for verification
echo "Recording initial site count..."
INITIAL_COUNT=$(matomo_query "SELECT COUNT(*) FROM matomo_site" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_site_count
echo "Initial site count: $INITIAL_COUNT"

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
echo "=== Add Website Task Setup Complete ==="
echo ""
echo "TASK: Add a new website to Matomo with the following information:"
echo ""
echo "  Website Name: TechBlog Demo"
echo "  Website URL:  https://techblog-demo.example.com"
echo "  Timezone:     Europe/London (select from Europe section in dropdown)"
echo "  Currency:     USD (US Dollar)"
echo ""
echo "Login credentials: admin / Admin12345"
echo ""
echo "Navigate to: Administration > Websites > Manage > Add a new website"
echo ""
