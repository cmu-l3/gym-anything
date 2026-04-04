#!/bin/bash
set -e
echo "=== Setting up Export Filtered Leads task ==="

source /workspace/scripts/task_utils.sh

# 1. ensure vicidial is running
vicidial_ensure_running

# 2. Clear downloads to ensure we detect NEW files
rm -rf /home/ga/Downloads/*
mkdir -p /home/ga/Downloads
chown ga:ga /home/ga/Downloads

# 3. Setup Database State (Deterministic Data)
# We need List 9001 to exist and contain specific leads (FL and non-FL) to test filtering.
echo "Configuring database with test leads..."

# Wait for DB
for i in {1..30}; do
    if docker exec vicidial mysql -ucron -p1234 -D asterisk -e "SELECT 1" >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

# Clean existing list 9001 data
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "DELETE FROM vicidial_list WHERE list_id='9001';"
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "DELETE FROM vicidial_lists WHERE list_id='9001';"

# Create List 9001
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "INSERT INTO vicidial_lists (list_id, list_name, list_description, active, campaign_id) VALUES ('9001', 'Test List 9001', 'Mixed States List', 'Y', 'TESTCAMP');"

# Insert Leads: 2 FL, 2 NY, 1 CA
# Fields: lead_id, list_id, first_name, last_name, state, phone_number
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "
INSERT INTO vicidial_list (lead_id, list_id, first_name, last_name, state, phone_number, status) VALUES 
(1001, '9001', 'Florida', 'Man', 'FL', '3055550001', 'NEW'),
(1002, '9001', 'Miami', 'Vice', 'FL', '3055550002', 'NEW'),
(1003, '9001', 'Empire', 'State', 'NY', '2125550001', 'NEW'),
(1004, '9001', 'Big', 'Apple', 'NY', '2125550002', 'NEW'),
(1005, '9001', 'Golden', 'Gate', 'CA', '4155550001', 'NEW');
"

echo "Database setup complete: 5 leads inserted (2 FL, 2 NY, 1 CA)."

# Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 4. Launch Firefox
# Navigate to Admin > Lists (Lists is a good starting point, but Admin home is fine)
VICIDIAL_ADMIN_URL="${VICIDIAL_ADMIN_URL:-http://localhost/vicidial/admin.php}"

if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$VICIDIAL_ADMIN_URL' > /dev/null 2>&1 &"
    sleep 5
fi

# Wait for window
wait_for_window "firefox\|mozilla\|vicidial" 30

# Focus and maximize
focus_firefox
maximize_active_window

# Handle Login if needed (standard credentials)
# Note: task_utils/vicidial env usually handles auth via URL or manual entry. 
# We'll assume the agent needs to login or is presented with the login screen.
# The previous tasks suggest auto-login might not persist, so we leave the agent at the login screen 
# or logged in if session persists. 
# We will just ensure the window is ready.

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="