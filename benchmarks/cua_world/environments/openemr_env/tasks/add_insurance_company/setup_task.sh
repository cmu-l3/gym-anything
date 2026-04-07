#!/bin/bash
# Setup script for Add Insurance Company task

echo "=== Setting up Add Insurance Company Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target insurance company name (for cleanup and verification)
TARGET_COMPANY="Blue Cross Blue Shield of Massachusetts"

# Remove any existing test insurance company to ensure clean state
echo "Cleaning up any existing test data..."
docker exec openemr-mysql mysql -u openemr -popenemr openemr -e \
    "DELETE FROM insurance_companies WHERE name LIKE '%Blue Cross%Massachusetts%' OR name LIKE '%BCBS%Massachusetts%' OR name LIKE '%BCBS%MA%'" 2>/dev/null || true

# Record initial insurance company count
echo "Recording initial insurance company count..."
INITIAL_COUNT=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT COUNT(*) FROM insurance_companies" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_insurance_count.txt
echo "Initial insurance company count: $INITIAL_COUNT"

# Record highest existing insurance company ID (to detect new entries)
HIGHEST_ID=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT COALESCE(MAX(id), 0) FROM insurance_companies" 2>/dev/null || echo "0")
echo "$HIGHEST_ID" > /tmp/initial_max_insurance_id.txt
echo "Highest existing insurance ID: $HIGHEST_ID"

# Record task start timestamp for anti-gaming checks
date +%s > /tmp/task_start_time.txt
echo "Task start timestamp: $(cat /tmp/task_start_time.txt)"

# List current insurance companies for debugging
echo ""
echo "=== Current Insurance Companies (sample) ==="
docker exec openemr-mysql mysql -u openemr -popenemr openemr -e \
    "SELECT id, name, city, state FROM insurance_companies ORDER BY id DESC LIMIT 5" 2>/dev/null || true
echo ""

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
take_screenshot /tmp/task_initial.png

echo ""
echo "=== Add Insurance Company Task Setup Complete ==="
echo ""
echo "Task Instructions:"
echo "  1. Log in to OpenEMR"
echo "     - Username: admin"
echo "     - Password: pass"
echo ""
echo "  2. Navigate to Administration > Practice Settings > Insurance Companies"
echo "     (Path may vary: look for Insurance Companies under Admin/Practice menus)"
echo ""
echo "  3. Add a new insurance company with these details:"
echo "     - Company Name: Blue Cross Blue Shield of Massachusetts"
echo "     - Address: 101 Huntington Avenue, Suite 1300"
echo "     - City: Boston"
echo "     - State: MA"
echo "     - Zip Code: 02199"
echo "     - Phone: (800) 262-2583"
echo ""
echo "  4. Save the new insurance company record"
echo ""