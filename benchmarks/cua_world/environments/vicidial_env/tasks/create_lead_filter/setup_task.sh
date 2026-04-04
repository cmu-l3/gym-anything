#!/bin/bash
set -e

echo "=== Setting up Create Lead Filter task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Vicidial is running
vicidial_ensure_running

# Record initial filter count for anti-gaming
echo "Recording initial filter count..."
INITIAL_COUNT=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e "SELECT COUNT(*) FROM vicidial_lead_filters;" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_filter_count.txt
echo "Initial count: $INITIAL_COUNT"

# Clean state: Ensure the target filter does not exist
echo "Ensuring target filter SOUTHEAST4 does not exist..."
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "DELETE FROM vicidial_lead_filters WHERE lead_filter_id='SOUTHEAST4';" 2>/dev/null || true

# Prepare Context Data: Load US Senators list if not present (List 9001)
# This provides the "context" mentioned in the rationale, even if we are just making a filter.
echo "Checking for US Senators data..."
if ! docker exec vicidial mysql -ucron -p1234 -D asterisk -e "SELECT list_id FROM vicidial_lists WHERE list_id='9001'" | grep -q 9001; then
    echo "Loading US Senators list context..."
    # We won't fully load the leads to save time, but we'll ensure the list object exists
    # so the agent sees a realistic environment.
    docker exec vicidial mysql -ucron -p1234 -D asterisk -e \
        "INSERT INTO vicidial_lists (list_id, list_name, campaign_id, active) VALUES ('9001', 'US Senators 2026', 'TESTCAMP', 'Y');" \
        2>/dev/null || true
fi

# Launch Firefox to the Admin Filters page (or main admin page)
# Filters URL usually involves section params, but main admin is safer start.
START_URL="${VICIDIAL_ADMIN_URL}"

# Restart Firefox for a clean session
pkill -f firefox 2>/dev/null || true
sleep 2

echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox --new-window '${START_URL}' > /tmp/firefox_vicidial.log 2>&1 &"

# Wait for window
wait_for_window "firefox\|mozilla\|vicidial" 30 || true

# Focus and maximize
focus_firefox
maximize_active_window

# Handle Login if needed (standard for this env)
echo "Handling login..."
sleep 2
DISPLAY=:1 xdotool type --delay 50 "6666"
DISPLAY=:1 xdotool key Tab
DISPLAY=:1 xdotool type --delay 50 "andromeda"
DISPLAY=:1 xdotool key Return
sleep 5

# Navigate specifically to the Filters section to assist the agent slightly in starting
# or just leave them at the main menu. The description says "Navigate to Filters", 
# so we can leave them at the Welcome screen or click Admin. 
# Let's leave them at the main Admin screen to test navigation.

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="