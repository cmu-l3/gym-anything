#!/bin/bash
# Setup script for Add List Option task
echo "=== Setting up Add List Option Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start timestamp: $(cat /tmp/task_start_time.txt)"

# Record initial count of ethnicity/race list options
echo "Recording initial list option count..."
INITIAL_COUNT=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT COUNT(*) FROM list_options WHERE list_id IN ('ethrace', 'ethnicity', 'race')" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_ethnicity_count.txt
echo "Initial ethnicity/race option count: $INITIAL_COUNT"

# Check if Haitian option already exists (for verification baseline)
EXISTING_HAITIAN=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT COUNT(*) FROM list_options WHERE (list_id IN ('ethrace', 'ethnicity', 'race')) AND LOWER(title) LIKE '%haitian%'" 2>/dev/null || echo "0")
echo "$EXISTING_HAITIAN" > /tmp/initial_haitian_count.txt
echo "Existing Haitian options: $EXISTING_HAITIAN"

# List current ethnicity options for debugging
echo ""
echo "=== Current ethnicity/race options in database ==="
docker exec openemr-mysql mysql -u openemr -popenemr openemr -e \
    "SELECT list_id, option_id, title, seq, activity FROM list_options WHERE list_id IN ('ethrace', 'ethnicity', 'race') ORDER BY list_id, seq" 2>/dev/null | head -30
echo "=== End of current options ==="
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

# Dismiss any dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial_state.png
echo "Initial screenshot saved to /tmp/task_initial_state.png"

echo ""
echo "=== Add List Option Task Setup Complete ==="
echo ""
echo "Task: Add 'Haitian' as a new ethnicity option"
echo ""
echo "Instructions:"
echo "  1. Log in to OpenEMR (Username: admin, Password: pass)"
echo "  2. Navigate to Administration → Lists"
echo "  3. Select the 'Ethnicity' or 'Race' list from the dropdown"
echo "  4. Add a new option:"
echo "     - ID/Code: haitian"
echo "     - Title: Haitian"
echo "     - Order: Any number (e.g., 90)"
echo "     - Active: Yes/Enabled"
echo "  5. Save the new option"
echo ""