#!/bin/bash
set -e

echo "=== Setting up Add Custom Lead Fields task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Vicidial is running
vicidial_ensure_running

# Wait for database to be ready
echo "Waiting for Vicidial MySQL..."
for i in {1..30}; do
    if docker exec vicidial mysql -ucron -p1234 -D asterisk -e "SELECT 1;" >/dev/null 2>&1; then
        break
    fi
    sleep 2
done

# Prepare Database State
echo "Preparing List 8501..."

# 1. Clean up any previous attempts (delete list, fields, and custom table)
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "
    DELETE FROM vicidial_lists WHERE list_id='8501';
    DELETE FROM vicidial_list WHERE list_id='8501';
    DELETE FROM vicidial_lists_fields WHERE list_id='8501';
    DROP TABLE IF EXISTS custom_8501;
" 2>/dev/null || true

# 2. Create the list
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "
    INSERT INTO vicidial_lists (list_id, list_name, campaign_id, active, list_description) 
    VALUES ('8501', 'US Senator Advocacy', 'TESTCAMP', 'Y', 'Advocacy campaign targeting US Senate offices');
"

# 3. Insert sample leads (Real Data: US Senators)
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "
    INSERT INTO vicidial_list (list_id, phone_number, first_name, last_name, state, city, address1, status) VALUES 
    ('8501', '2022243121', 'Chuck', 'Schumer', 'NY', 'Washington', '322 Hart Senate Office Building', 'NEW'),
    ('8501', '2022245653', 'Mitch', 'McConnell', 'KY', 'Washington', '317 Russell Senate Office Building', 'NEW'),
    ('8501', '2022245344', 'Dick', 'Durbin', 'IL', 'Washington', '711 Hart Senate Office Building', 'NEW'),
    ('8501', '2022244944', 'John', 'Thune', 'SD', 'Washington', '511 Dirksen Senate Office Building', 'NEW'),
    ('8501', '2022243553', 'Patty', 'Murray', 'WA', 'Washington', '154 Russell Senate Office Building', 'NEW');
"

# Record initial field count (should be 0)
INITIAL_COUNT=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e \
    "SELECT COUNT(*) FROM vicidial_lists_fields WHERE list_id='8501';" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_field_count.txt
echo "Initial custom fields count: $INITIAL_COUNT"

# Setup Firefox
echo "Launching Firefox..."
# Start at the Lists menu to save time, but require login if needed
TARGET_URL="${VICIDIAL_ADMIN_URL}?ADD=100" 

if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox '$TARGET_URL' > /tmp/firefox.log 2>&1 &"
    sleep 5
fi

wait_for_window "Firefox" 30
maximize_active_window

# Handle Login if redirected
# (Vicidial basic auth usually handled by browser or URL params if configured, 
# but the env setup might rely on manual login or saved session. 
# We'll try to pre-fill if on login screen)
sleep 2
DISPLAY=:1 xdotool type "6666" 2>/dev/null || true
DISPLAY=:1 xdotool key Tab 2>/dev/null || true
DISPLAY=:1 xdotool type "andromeda" 2>/dev/null || true
DISPLAY=:1 xdotool key Return 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="