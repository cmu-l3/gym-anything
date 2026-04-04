#!/bin/bash
set -e

echo "=== Setting up Bulk Lead Correction Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Vicidial is running
vicidial_ensure_running

# Wait for DB to be fully ready
echo "Waiting for database..."
sleep 5

# --- DATA PREPARATION ---

# 1. Clean up existing data for List 9999 to ensure a clean state
echo "Cleaning up old data..."
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "DELETE FROM vicidial_lists WHERE list_id='9999';" 2>/dev/null || true
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "DELETE FROM vicidial_list WHERE list_id='9999';" 2>/dev/null || true

# 2. Create List 9999
echo "Creating List 9999..."
docker exec vicidial mysql -ucron -p1234 -D asterisk -e \
    "INSERT INTO vicidial_lists (list_id, list_name, campaign_id, active, list_description) VALUES ('9999', 'DC Metro Errors', 'TESTCAMP', 'Y', 'Leads with typos');"

# 3. Insert Leads (5 Bad, 5 Good)
# We set entry_date to '2020-01-01 12:00:00' to test preservation
echo "Seeding leads..."

# Bad Leads (Washingtun)
docker exec vicidial mysql -ucron -p1234 -D asterisk -e \
    "INSERT INTO vicidial_list (entry_date, status, user, list_id, phone_code, phone_number, first_name, last_name, city, state) VALUES 
    ('2020-01-01 12:00:00', 'NEW', '6666', '9999', '1', '2025550101', 'John', 'Doe', 'Washingtun', 'DC'),
    ('2020-01-01 12:00:00', 'NEW', '6666', '9999', '1', '2025550102', 'Jane', 'Smith', 'Washingtun', 'DC'),
    ('2020-01-01 12:00:00', 'NEW', '6666', '9999', '1', '2025550103', 'Bob', 'Johnson', 'Washingtun', 'DC'),
    ('2020-01-01 12:00:00', 'NEW', '6666', '9999', '1', '2025550104', 'Alice', 'Williams', 'Washingtun', 'DC'),
    ('2020-01-01 12:00:00', 'NEW', '6666', '9999', '1', '2025550105', 'Charlie', 'Brown', 'Washingtun', 'DC');"

# Good Leads (Washington) - Controls
docker exec vicidial mysql -ucron -p1234 -D asterisk -e \
    "INSERT INTO vicidial_list (entry_date, status, user, list_id, phone_code, phone_number, first_name, last_name, city, state) VALUES 
    ('2020-01-01 12:00:00', 'NEW', '6666', '9999', '1', '2025550106', 'David', 'Miller', 'Washington', 'DC'),
    ('2020-01-01 12:00:00', 'NEW', '6666', '9999', '1', '2025550107', 'Eva', 'Davis', 'Washington', 'DC'),
    ('2020-01-01 12:00:00', 'NEW', '6666', '9999', '1', '2025550108', 'Frank', 'Garcia', 'Washington', 'DC'),
    ('2020-01-01 12:00:00', 'NEW', '6666', '9999', '1', '2025550109', 'Grace', 'Rodriguez', 'Washington', 'DC'),
    ('2020-01-01 12:00:00', 'NEW', '6666', '9999', '1', '2025550110', 'Henry', 'Wilson', 'Washington', 'DC');"

# --- BROWSER SETUP ---

# Start Firefox at the Admin page
echo "Launching Firefox..."
pkill -f firefox 2>/dev/null || true

# Start at Load Leads page directly to be helpful, or just Admin
TARGET_URL="${VICIDIAL_ADMIN_URL}?ADD=100" # ADD=100 is typically Lists or similar, we'll aim for Admin root
su - ga -c "DISPLAY=:1 firefox '${TARGET_URL}' > /dev/null 2>&1 &"

# Wait for window
wait_for_window "firefox" 30
maximize_active_window

# Authenticate if needed (Basic Auth handling)
# Vicidial container often uses Basic Auth
echo "Handling authentication..."
sleep 2
DISPLAY=:1 xdotool type "6666"
DISPLAY=:1 xdotool key Tab
DISPLAY=:1 xdotool type "andromeda"
DISPLAY=:1 xdotool key Return
sleep 3

# Create a clean working directory for the agent to make their CSV
mkdir -p /home/ga/Documents/Corrections
chown ga:ga /home/ga/Documents/Corrections

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="