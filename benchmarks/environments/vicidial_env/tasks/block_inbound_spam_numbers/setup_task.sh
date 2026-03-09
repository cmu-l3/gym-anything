#!/bin/bash
set -e

echo "=== Setting up block_inbound_spam_numbers task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure Vicidial is running
vicidial_ensure_running

# 2. Prepare Data: Create the spam number file
mkdir -p /home/ga/Documents/VicidialData
echo "2025550188" > /home/ga/Documents/VicidialData/spam_number_to_block.txt
chown -R ga:ga /home/ga/Documents/VicidialData

# 3. Clean State: Remove the filter group if it exists from previous runs
echo "Cleaning up previous task artifacts..."
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "DELETE FROM vicidial_filter_phone_groups WHERE filter_phone_group_id='SPAMBLOCK';" 2>/dev/null || true
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "DELETE FROM vicidial_filter_phone_numbers WHERE filter_phone_group_id='SPAMBLOCK';" 2>/dev/null || true

# 4. Ensure the Target DID exists
# We insert it if it doesn't exist, resetting it to default state (no filtering)
echo "Ensuring target DID 8885550100 exists..."
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "
INSERT IGNORE INTO vicidial_inbound_dids (did_pattern, did_description, did_active, did_route, filter_inbound_number, filter_phone_group_id, filter_action) 
VALUES ('8885550100', 'Main Toll Free', 'Y', 'EXTEN', 'DISABLED', '', 'MESSAGE');
UPDATE vicidial_inbound_dids SET filter_inbound_number='DISABLED', filter_phone_group_id='', filter_action='MESSAGE' WHERE did_pattern='8885550100';
"

# 5. Ensure Admin User 6666 has permissions for Inbound
echo "Granting permissions..."
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "UPDATE vicidial_users SET modify_inbound_dids='1', modify_filter_phone_groups='1' WHERE user='6666';"

# 6. Record Start Time
date +%s > /tmp/task_start_time.txt

# 7. Launch Firefox to Admin Panel
# We use the generic login URL
START_URL="${VICIDIAL_ADMIN_URL}"
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox '${START_URL}' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

wait_for_window "firefox\|mozilla\|vicidial" 30
focus_firefox
maximize_active_window

# 8. Capture Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="