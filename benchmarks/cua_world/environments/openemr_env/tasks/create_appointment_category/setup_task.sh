#!/bin/bash
# Setup script for Create Appointment Category task

echo "=== Setting up Create Appointment Category Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "Task start timestamp: $(cat /tmp/task_start_time.txt)"

# Record baseline category count and max ID
echo "Recording baseline category data..."
BASELINE_MAX_ID=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT COALESCE(MAX(pc_catid), 0) FROM openemr_postcalendar_categories" 2>/dev/null || echo "0")
echo "$BASELINE_MAX_ID" > /tmp/baseline_category_id.txt
echo "Baseline max category ID: $BASELINE_MAX_ID"

BASELINE_COUNT=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT COUNT(*) FROM openemr_postcalendar_categories" 2>/dev/null || echo "0")
echo "$BASELINE_COUNT" > /tmp/baseline_category_count.txt
echo "Baseline category count: $BASELINE_COUNT"

# Clean slate - remove any existing Telehealth category from previous runs
echo "Cleaning up any existing Telehealth categories..."
docker exec openemr-mysql mysql -u openemr -popenemr openemr -e \
    "DELETE FROM openemr_postcalendar_categories WHERE pc_catname LIKE '%Telehealth%' OR pc_catname LIKE '%telehealth%'" 2>/dev/null || true

# Update baseline after cleanup
BASELINE_MAX_ID=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT COALESCE(MAX(pc_catid), 0) FROM openemr_postcalendar_categories" 2>/dev/null || echo "0")
echo "$BASELINE_MAX_ID" > /tmp/baseline_category_id.txt

BASELINE_COUNT=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT COUNT(*) FROM openemr_postcalendar_categories" 2>/dev/null || echo "0")
echo "$BASELINE_COUNT" > /tmp/baseline_category_count.txt

echo "Updated baseline - Max ID: $BASELINE_MAX_ID, Count: $BASELINE_COUNT"

# List existing categories for reference
echo ""
echo "=== Existing appointment categories ==="
docker exec openemr-mysql mysql -u openemr -popenemr openemr -e \
    "SELECT pc_catid, pc_catname, pc_duration, pc_catcolor FROM openemr_postcalendar_categories ORDER BY pc_catid" 2>/dev/null || true
echo ""

# Ensure Firefox is running with OpenEMR
echo "Ensuring Firefox is running..."
OPENEMR_URL="http://localhost/interface/login/login.php?site=default"

if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$OPENEMR_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Wait for Firefox window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "firefox\|mozilla"; then
        echo "Firefox window detected"
        break
    fi
    sleep 1
done

# Focus and maximize Firefox window
echo "Focusing Firefox window..."
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

if [ -f /tmp/task_initial.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Create Appointment Category Task Setup Complete ==="
echo ""
echo "TASK: Create a new appointment category for telehealth visits"
echo ""
echo "Instructions:"
echo "  1. Log in to OpenEMR (Username: admin, Password: pass)"
echo "  2. Navigate to Administration menu"
echo "  3. Find Calendar settings/Categories"
echo "  4. Add a new category:"
echo "     - Name: Telehealth Visit"
echo "     - Duration: 20 minutes"
echo "     - Color: Any distinct color"
echo "     - Description: Brief description of video consultations"
echo "  5. Save the category"
echo ""