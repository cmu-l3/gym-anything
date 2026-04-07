#!/bin/bash
# Setup script for Create Facility Location Task

echo "=== Setting up Create Facility Location Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "Task start timestamp: $(cat /tmp/task_start_time.txt)"

# Record initial facility count for verification
echo "Recording initial facility count..."
INITIAL_COUNT=$(openemr_query "SELECT COUNT(*) FROM facility" 2>/dev/null || echo "1")
echo "$INITIAL_COUNT" > /tmp/initial_facility_count.txt
echo "Initial facility count: $INITIAL_COUNT"

# Record existing facility names (to detect pre-existing matching facilities)
echo "Recording existing facility names..."
openemr_query "SELECT id, name FROM facility ORDER BY id" > /tmp/initial_facilities.txt 2>/dev/null || echo "1	Your Clinic Name Here" > /tmp/initial_facilities.txt
echo "Existing facilities:"
cat /tmp/initial_facilities.txt

# Check if target facility already exists (adversarial case)
EXISTING_TARGET=$(openemr_query "SELECT COUNT(*) FROM facility WHERE name LIKE '%Riverside%' OR name LIKE '%East%'" 2>/dev/null || echo "0")
echo "$EXISTING_TARGET" > /tmp/existing_target_count.txt
if [ "$EXISTING_TARGET" -gt "0" ]; then
    echo "WARNING: A facility matching target name already exists!"
fi

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

# Take initial screenshot for audit verification
take_screenshot /tmp/task_initial.png
echo "Initial screenshot saved to /tmp/task_initial.png"

echo ""
echo "=== Create Facility Location Task Setup Complete ==="
echo ""
echo "Task: Add a new satellite clinic facility to OpenEMR"
echo ""
echo "Facility Details to Enter:"
echo "  - Name: Riverside Family Medicine - East"
echo "  - Street: 450 Harbor View Drive, Suite 200"
echo "  - City: Springfield"
echo "  - State: Massachusetts"
echo "  - Postal Code: 01109"
echo "  - Phone: (413) 555-0192"
echo "  - Fax: (413) 555-0193"
echo "  - Federal Tax ID: 04-3892156"
echo "  - Facility NPI: 1234567893"
echo "  - Service Location: Yes"
echo "  - Billing Location: Yes"
echo ""
echo "Navigate to: Administration > Facilities > Add Facility"
echo ""