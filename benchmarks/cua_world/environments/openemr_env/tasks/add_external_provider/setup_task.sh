#!/bin/bash
# Setup script for Add External Provider task

echo "=== Setting up Add External Provider Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start timestamp: $(cat /tmp/task_start_time.txt)"

# Record initial address book entry count
echo "Recording initial address book state..."

# Check addresses table
INITIAL_ADDR_COUNT=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e "SELECT COUNT(*) FROM addresses" 2>/dev/null || echo "0")
echo "$INITIAL_ADDR_COUNT" > /tmp/initial_address_count.txt
echo "Initial addresses table count: $INITIAL_ADDR_COUNT"

# Check users table for abook entries (some versions store address book here)
INITIAL_USER_ABOOK=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e "SELECT COUNT(*) FROM users WHERE abook_type IS NOT NULL AND abook_type != ''" 2>/dev/null || echo "0")
echo "$INITIAL_USER_ABOOK" > /tmp/initial_user_abook_count.txt
echo "Initial users abook entries: $INITIAL_USER_ABOOK"

# Clean up any existing test entries (Springfield, MA with our test phone)
echo "Cleaning up any existing test entries..."
docker exec openemr-mysql mysql -u openemr -popenemr openemr -e "DELETE FROM addresses WHERE city='Springfield' AND state='MA' AND (zip='01103' OR zip LIKE '01103%')" 2>/dev/null || true
docker exec openemr-mysql mysql -u openemr -popenemr openemr -e "DELETE FROM users WHERE city='Springfield' AND state='MA' AND abook_type IS NOT NULL" 2>/dev/null || true

# Verify cleanup
POST_CLEANUP_COUNT=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e "SELECT COUNT(*) FROM addresses WHERE city='Springfield' AND state='MA'" 2>/dev/null || echo "0")
echo "Address entries for Springfield, MA after cleanup: $POST_CLEANUP_COUNT"

# Ensure Firefox is running on OpenEMR login page
echo "Ensuring Firefox is running..."
OPENEMR_URL="http://localhost/interface/login/login.php?site=default"

if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$OPENEMR_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Wait for Firefox window
if ! wait_for_window "firefox\|mozilla\|OpenEMR" 30; then
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

# Take initial screenshot
echo "Capturing initial screenshot..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

if [ -f /tmp/task_initial.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Add External Provider Task Setup Complete ==="
echo ""
echo "Task: Add a new external referring physician to OpenEMR's Address Book"
echo ""
echo "Provider Details:"
echo "  Name: Dr. Sarah Mitchell, MD"
echo "  Specialty: Gastroenterology"
echo "  Organization: Springfield GI Associates"
echo "  Address: 456 Medical Center Drive, Suite 200"
echo "           Springfield, MA 01103"
echo "  Phone: (413) 555-7890"
echo "  Fax: (413) 555-7891"
echo "  Email: s.mitchell@springfieldgi.example.com"
echo "  NPI: 1234567893"
echo ""
echo "Login: admin / pass"
echo "Navigate to: Miscellaneous > Address Book (or Administration > Address Book)"
echo ""