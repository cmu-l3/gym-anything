#!/bin/bash
# Setup script for Add Pharmacy task
# Prepares the environment and records initial state for verification

echo "=== Setting up Add Pharmacy Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Record initial pharmacy count
echo "Recording initial pharmacy count..."
INITIAL_COUNT=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e "SELECT COUNT(*) FROM pharmacies" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_pharmacy_count.txt
echo "Initial pharmacy count: $INITIAL_COUNT"

# Clean up any pre-existing test pharmacy to ensure clean slate
echo "Cleaning up any pre-existing test pharmacy..."
docker exec openemr-mysql mysql -u openemr -popenemr openemr -e "DELETE FROM pharmacies WHERE name LIKE '%CVS%8472%' OR (address_line_1 LIKE '%2150 Commonwealth%' AND city='Boston')" 2>/dev/null || true

# Get updated count after cleanup
CLEAN_COUNT=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e "SELECT COUNT(*) FROM pharmacies" 2>/dev/null || echo "0")
echo "$CLEAN_COUNT" > /tmp/initial_pharmacy_count.txt
echo "Pharmacy count after cleanup: $CLEAN_COUNT"

# List existing pharmacies for debugging
echo ""
echo "=== Existing pharmacies in database ==="
docker exec openemr-mysql mysql -u openemr -popenemr openemr -e "SELECT id, name, city, state FROM pharmacies ORDER BY id DESC LIMIT 5" 2>/dev/null || echo "Could not query pharmacies"
echo ""

# Ensure Firefox is running with OpenEMR
echo "Ensuring Firefox is running..."
OPENEMR_URL="http://localhost/interface/login/login.php?site=default"

if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox with OpenEMR..."
    su - ga -c "DISPLAY=:1 firefox '$OPENEMR_URL' > /tmp/firefox_pharmacy_task.log 2>&1 &"
    sleep 5
fi

# Wait for Firefox window to appear
echo "Waiting for Firefox window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla"; then
        echo "Firefox window detected after ${i}s"
        break
    fi
    sleep 1
done

# Focus and maximize Firefox window
echo "Configuring Firefox window..."
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    echo "Firefox window maximized and focused: $WID"
fi

# Dismiss any startup dialogs
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.3
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot for audit trail
echo "Capturing initial screenshot..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_initial_state.png 2>/dev/null || true

if [ -f /tmp/task_initial_state.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial_state.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Add Pharmacy Task Setup Complete ==="
echo ""
echo "TASK: Add New Pharmacy to System"
echo "================================="
echo ""
echo "Login Credentials:"
echo "  Username: admin"
echo "  Password: pass"
echo ""
echo "Pharmacy Details to Enter:"
echo "  Name: CVS Pharmacy #8472"
echo "  Address: 2150 Commonwealth Avenue"
echo "  City: Boston"
echo "  State: MA"
echo "  Zip: 02135"
echo "  Phone: (617) 555-0142"
echo "  Fax: (617) 555-0143"
echo "  Email: rx8472@cvs.com"
echo "  NPI: 1234567890"
echo ""
echo "Navigate to Administration > Practice > Pharmacies"
echo "Add the new pharmacy with all details above."
echo ""