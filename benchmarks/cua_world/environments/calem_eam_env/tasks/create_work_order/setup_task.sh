#!/bin/bash
# Setup script for Create Work Order task

echo "=== Setting up Create Work Order Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record initial work order count for verification
echo "Recording initial work order count..."
INITIAL_COUNT=$(calemeam_query "SELECT COUNT(*) FROM workorder" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_wo_count
echo "Initial work order count: $INITIAL_COUNT"

# Ensure Firefox is running and focused on CalemEAM
echo "Ensuring Firefox is running..."
CALEMEAM_URL="http://localhost/CalemEAM/"

if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox-esr '$CALEMEAM_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Wait for Firefox window
if ! wait_for_window "firefox\|mozilla\|CalemEAM\|calem" 30; then
    echo "WARNING: Firefox window not detected"
fi

# Focus Firefox window
echo "Focusing Firefox window..."
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Create Work Order Task Setup Complete ==="
echo ""
echo "Task Instructions:"
echo "  1. Log in to CalemEAM if not already logged in"
echo "     - Username: admin"
echo "     - Password: admin_password"
echo ""
echo "  2. Navigate to Work Order module"
echo ""
echo "  3. Create a new work order with:"
echo "     - Asset: 401-001 (100 HP compressor #1)"
echo "     - Description: Compressor bearing replacement and alignment check"
echo "     - Priority: P2 (Urgent)"
echo ""
echo "  4. Save the work order"
echo ""
