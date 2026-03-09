#!/bin/bash
set -e

echo "=== Setting up Reset List Leads task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Vicidial is running
vicidial_ensure_running

# Wait for MySQL to be fully ready
echo "Waiting for Vicidial MySQL..."
for i in {1..30}; do
    if docker exec vicidial mysql -ucron -p1234 -D asterisk -e "SELECT 1;" >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

# Prepare Database State
# We need List 9001 to exist and have leads with called_since_last_reset='Y'
echo "Preparing List 9001 data..."

# 1. Clean up existing list 9001 data
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "DELETE FROM vicidial_lists WHERE list_id='9001';" 2>/dev/null || true
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "DELETE FROM vicidial_list WHERE list_id='9001';" 2>/dev/null || true

# 2. Create the List
docker exec vicidial mysql -ucron -p1234 -D asterisk -e \
    "INSERT INTO vicidial_lists (list_id, list_name, list_description, active, campaign_id) VALUES ('9001', 'US Senators 2026', 'Primary Campaign List', 'Y', 'TESTCAMP');"

# 3. Insert Leads with 'Y' (Called) status
# We insert 10 of each target status (B, N, A) and 5 of each protected status (SALE, DNC)
# Total 40 leads
echo "Inserting leads..."

# Status B (Busy)
for i in {1..10}; do
    docker exec vicidial mysql -ucron -p1234 -D asterisk -e \
        "INSERT INTO vicidial_list (lead_id, list_id, status, phone_number, called_since_last_reset, gmt_offset_now) VALUES (null, '9001', 'B', '10000000$i', 'Y', -5.00);"
done

# Status N (No Answer)
for i in {11..20}; do
    docker exec vicidial mysql -ucron -p1234 -D asterisk -e \
        "INSERT INTO vicidial_list (lead_id, list_id, status, phone_number, called_since_last_reset, gmt_offset_now) VALUES (null, '9001', 'N', '10000000$i', 'Y', -5.00);"
done

# Status A (Answering Machine)
for i in {21..30}; do
    docker exec vicidial mysql -ucron -p1234 -D asterisk -e \
        "INSERT INTO vicidial_list (lead_id, list_id, status, phone_number, called_since_last_reset, gmt_offset_now) VALUES (null, '9001', 'A', '10000000$i', 'Y', -5.00);"
done

# Status SALE (Protected)
for i in {31..35}; do
    docker exec vicidial mysql -ucron -p1234 -D asterisk -e \
        "INSERT INTO vicidial_list (lead_id, list_id, status, phone_number, called_since_last_reset, gmt_offset_now) VALUES (null, '9001', 'SALE', '10000000$i', 'Y', -5.00);"
done

# Status DNC (Protected)
for i in {36..40}; do
    docker exec vicidial mysql -ucron -p1234 -D asterisk -e \
        "INSERT INTO vicidial_list (lead_id, list_id, status, phone_number, called_since_last_reset, gmt_offset_now) VALUES (null, '9001', 'DNC', '10000000$i', 'Y', -5.00);"
done

# Record initial count of 'Y' leads (should be 40)
INITIAL_Y_COUNT=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e "SELECT count(*) FROM vicidial_list WHERE list_id='9001' AND called_since_last_reset='Y';")
echo "$INITIAL_Y_COUNT" > /tmp/initial_y_count.txt
echo "Initial 'Y' leads: $INITIAL_Y_COUNT"

# Launch Firefox to Admin Panel
# Pre-authenticate to avoid basic auth popup issues
VICIDIAL_ADMIN_URL="http://localhost/vicidial/admin.php"
START_URL="${VICIDIAL_ADMIN_URL}?ADD=100" # Goes to Lists section

pkill -f firefox 2>/dev/null || true

# Start Firefox
su - ga -c "DISPLAY=:1 firefox --new-window '${START_URL}' > /tmp/firefox_task.log 2>&1 &"

# Wait for window
wait_for_window "firefox|mozilla|vicidial" 30
focus_firefox
maximize_active_window

# Handle Login if redirected
sleep 3
# Simple xdotool sequence to login if needed (User: 6666, Pass: andromeda)
# We assume standard login form positions if not auto-logged in by basic auth URL params (which Vicidial sometimes supports, but standard is basic auth)
# This environment script handles basic auth via URL usually, but we'll be safe.
DISPLAY=:1 xdotool type --delay 50 "6666" 2>/dev/null || true
DISPLAY=:1 xdotool key Tab 2>/dev/null || true
DISPLAY=:1 xdotool type --delay 50 "andromeda" 2>/dev/null || true
DISPLAY=:1 xdotool key Return 2>/dev/null || true

sleep 5

# Final setup screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="