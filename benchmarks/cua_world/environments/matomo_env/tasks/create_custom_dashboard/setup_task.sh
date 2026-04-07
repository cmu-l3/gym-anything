#!/bin/bash
# Setup script for Create Custom Dashboard task

echo "=== Setting up Create Custom Dashboard Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start timestamp (critical for anti-gaming)
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/task_start_timestamp
echo "Task start timestamp: $TASK_START"

# Ensure Matomo is installed
if ! matomo_is_installed; then
    echo "ERROR: Matomo not installed. Please run installation first."
    exit 1
fi

# Populate synthetic visitor data so widgets have content
echo "Populating synthetic visitor data..."
if [ -x /workspace/scripts/populate_visitor_data.sh ]; then
    /workspace/scripts/populate_visitor_data.sh > /dev/null 2>&1 || echo "Warning: Data population failed"
else
    echo "Warning: Data population script not found"
fi

# Clean up any previous attempts (delete dashboard if it exists)
EXPECTED_NAME="Weekly Marketing Review"
echo "Cleaning up pre-existing dashboard: $EXPECTED_NAME"
matomo_query "DELETE FROM matomo_user_dashboard WHERE LOWER(name)=LOWER('$EXPECTED_NAME')" 2>/dev/null || true

# Record initial state
# We need the max iddashboard to ensure the new one is actually new
MAX_ID=$(matomo_query "SELECT MAX(iddashboard) FROM matomo_user_dashboard" 2>/dev/null)
if [ -z "$MAX_ID" ] || [ "$MAX_ID" = "NULL" ]; then
    MAX_ID=0
fi
echo "$MAX_ID" > /tmp/initial_max_dashboard_id
echo "Initial Max Dashboard ID: $MAX_ID"

# Record initial count
INITIAL_COUNT=$(matomo_query "SELECT COUNT(*) FROM matomo_user_dashboard" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_dashboard_count

# Ensure Firefox is running on Matomo Dashboard
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
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Dismiss any Firefox first-run dialogs or Matomo tours
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot for audit
take_screenshot /tmp/task_initial_screenshot.png
echo "Initial screenshot saved"

echo ""
echo "=== Setup Complete ==="
echo "TASK: Create 'Weekly Marketing Review' dashboard with 3 widgets:"
echo "1. Visits Overview"
echo "2. Referrer Type"
echo "3. Device Type"