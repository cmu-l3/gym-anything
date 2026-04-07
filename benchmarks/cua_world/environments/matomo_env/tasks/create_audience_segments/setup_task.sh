#!/bin/bash
# Setup script for Create Audience Segments task

echo "=== Setting up Create Audience Segments Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Ensure Matomo is running
if ! matomo_is_installed; then
    echo "ERROR: Matomo not fully installed. Please check environment."
fi

# Clean up any pre-existing segments with the target names to ensure a clean slate
# This prevents previous run artifacts from confusing the verification
echo "Cleaning up old segments..."
matomo_query "DELETE FROM matomo_segment WHERE name IN ('High-Value Desktop Users', 'Bounced Mobile Visitors')" 2>/dev/null || true

# Record initial segment count
INITIAL_COUNT=$(matomo_query "SELECT COUNT(*) FROM matomo_segment WHERE deleted=0" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_segment_count
echo "Initial segment count: $INITIAL_COUNT"

# Record initial segment IDs (for strict anti-gaming)
matomo_query "SELECT idsegment FROM matomo_segment WHERE deleted=0" 2>/dev/null | tr '\n' ',' | sed 's/,$//' > /tmp/initial_segment_ids
echo "Initial IDs: $(cat /tmp/initial_segment_ids)"

# Record task start timestamp
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/task_start_timestamp

# Ensure Firefox is running and focused on Matomo Dashboard
echo "Starting Firefox..."
MATOMO_URL="http://localhost/"

# Kill existing instances
pkill -f firefox 2>/dev/null || true
sleep 2

su - ga -c "DISPLAY=:1 firefox '$MATOMO_URL' > /tmp/firefox_task.log 2>&1 &"
sleep 5

# Wait for window
if ! wait_for_window "firefox\|mozilla\|Matomo" 30; then
    echo "WARNING: Firefox window not detected"
fi

# Focus and maximize
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Dismiss any first-run dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Setup Complete ==="