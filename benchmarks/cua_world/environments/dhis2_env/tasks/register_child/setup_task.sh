#!/bin/bash
# Setup script for Register Child task

echo "=== Setting up Register Child Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Verify DHIS2 is running
echo "Checking DHIS2 health..."
if ! check_dhis2_health; then
    echo "WARNING: DHIS2 is not responding. Waiting..."
    sleep 30
    check_dhis2_health || echo "DHIS2 may not be fully ready"
fi

# Record initial tracked entity count for verification
echo "Recording initial tracked entity count..."
INITIAL_COUNT=$(dhis2_query "SELECT COUNT(*) FROM trackedentityinstance" 2>/dev/null | tr -d ' ' || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_tracked_entity_count
echo "Initial tracked entity count: $INITIAL_COUNT"

# Ensure Firefox is running and focused on DHIS2
echo "Ensuring Firefox is running..."
DHIS2_LOGIN_URL="http://localhost:8080/dhis-web-commons/security/login.action"

if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$DHIS2_LOGIN_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Wait for Firefox window
if ! wait_for_window "firefox\|mozilla\|DHIS" 30; then
    echo "WARNING: Firefox window not detected"
fi

# Focus Firefox window
echo "Focusing Firefox window..."
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    # Maximize window
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Click on center of screen to ensure desktop is selected
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 960 540 click 1" || true
sleep 0.5

# Focus Firefox again
if [ -n "$WID" ]; then
    focus_window "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Register Child Task Setup Complete ==="
echo ""
echo "Task Instructions:"
echo "  1. Log in to DHIS2 if not already logged in"
echo "     - Username: admin"
echo "     - Password: district"
echo ""
echo "  2. Navigate to the Tracker Capture app"
echo "     (Apps menu or search for 'Tracker Capture')"
echo ""
echo "  3. Select organisation unit: Ngelehun CHC"
echo "     (In the organisation unit tree on the left)"
echo ""
echo "  4. Select programme: Child Programme"
echo ""
echo "  5. Click 'Register' to add a new child"
echo ""
echo "  6. Fill in the child's details:"
echo "     - First Name: Aminata"
echo "     - Last Name: Kamara"
echo "     - Date of Birth: 2023-06-15"
echo "     - Sex: Female"
echo ""
echo "  7. Save the registration"
echo ""
