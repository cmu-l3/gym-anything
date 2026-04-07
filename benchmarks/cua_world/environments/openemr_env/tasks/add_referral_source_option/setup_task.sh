#!/bin/bash
# Setup script for Add Referral Source Option task

echo "=== Setting up Add Referral Source Option Task ==="

# Source shared utilities if available
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
fi

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start timestamp: $(cat /tmp/task_start_time.txt)"

# Record initial referral source count
echo "Recording initial referral source options..."
INITIAL_COUNT=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT COUNT(*) FROM list_options WHERE list_id='refsource'" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_refsource_count.txt
echo "Initial referral source count: $INITIAL_COUNT"

# Record all existing option_ids to detect new additions
echo "Recording existing option IDs..."
docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT option_id FROM list_options WHERE list_id='refsource'" 2>/dev/null > /tmp/initial_refsource_ids.txt || true

# List existing options for debugging
echo ""
echo "Current referral source options:"
docker exec openemr-mysql mysql -u openemr -popenemr openemr -e \
    "SELECT option_id, title, seq, activity FROM list_options WHERE list_id='refsource' ORDER BY seq" 2>/dev/null || true
echo ""

# Verify Westside doesn't already exist - remove if it does for clean test
EXISTING=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT COUNT(*) FROM list_options WHERE list_id='refsource' AND (LOWER(title) LIKE '%westside%' OR LOWER(option_id) LIKE '%westside%')" 2>/dev/null || echo "0")

if [ "$EXISTING" != "0" ]; then
    echo "WARNING: Westside option already exists - removing for clean test..."
    docker exec openemr-mysql mysql -u openemr -popenemr openemr -e \
        "DELETE FROM list_options WHERE list_id='refsource' AND (LOWER(title) LIKE '%westside%' OR LOWER(option_id) LIKE '%westside%')" 2>/dev/null || true
    
    # Update initial count after cleanup
    INITIAL_COUNT=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
        "SELECT COUNT(*) FROM list_options WHERE list_id='refsource'" 2>/dev/null || echo "0")
    echo "$INITIAL_COUNT" > /tmp/initial_refsource_count.txt
    echo "Updated initial count after cleanup: $INITIAL_COUNT"
fi

# Ensure Firefox is running with OpenEMR
OPENEMR_URL="http://localhost/interface/login/login.php?site=default"

if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$OPENEMR_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Wait for Firefox window to appear
echo "Waiting for Firefox window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|openemr"; then
        echo "Firefox window detected after ${i}s"
        break
    fi
    sleep 1
done

# Focus and maximize Firefox window
echo "Focusing and maximizing Firefox..."
sleep 2
DISPLAY=:1 wmctrl -r "firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "firefox" 2>/dev/null || true
sleep 1

# Take initial screenshot for evidence
echo "Capturing initial screenshot..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

if [ -f /tmp/task_initial.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Add a new referral source option to OpenEMR"
echo "======================================================="
echo ""
echo "Instructions:"
echo "  1. Log in to OpenEMR (Username: admin, Password: pass)"
echo "  2. Navigate to Administration > Lists"
echo "  3. Find the 'Referral Source' list (list_id: refsource)"
echo "  4. Add a new option:"
echo "     - Title: Westside Urgent Care"
echo "     - ID: westside_uc (or similar)"
echo "     - Mark as Active"
echo "  5. Save the new option"
echo ""
echo "The new referral source should appear in drop-downs when registering patients."
echo ""