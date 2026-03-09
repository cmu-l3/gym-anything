#!/bin/bash
set -e

echo "=== Setting up Bulk Reassign Leads Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Vicidial is running
vicidial_ensure_running

# Data paths
CSV_FILE="/home/ga/Documents/VicidialData/us_senators_vicidial_leads_2026-02-14.csv"
CONTAINER_CSV="/tmp/leads.csv"

# 1. Prepare Database State
echo "Resetting database state..."

# Copy CSV to container for loading
if [ -f "$CSV_FILE" ]; then
    docker cp "$CSV_FILE" vicidial:"$CONTAINER_CSV"
else
    echo "ERROR: Data file not found at $CSV_FILE"
    exit 1
fi

# SQL setup script
# - Clear lists 9001 and 9002
# - Re-create list definitions in vicidial_lists
# - Load leads into vicidial_list (List 9001)
cat > /tmp/setup_db.sql << EOF
USE asterisk;

-- Clear leads for these lists
DELETE FROM vicidial_list WHERE list_id IN ('9001', '9002');
DELETE FROM vicidial_lists WHERE list_id IN ('9001', '9002');

-- Create List Definitions
INSERT INTO vicidial_lists (list_id, list_name, campaign_id, active, list_description) VALUES 
('9001', 'US Senators General', 'TESTCAMP', 'Y', 'General list of US Senators'),
('9002', 'US Senators California', 'TESTCAMP', 'Y', 'Specific list for CA Senators');

-- Load Leads from CSV
-- Assuming standard Vicidial CSV layout (lead_id, entry_date, modify_date, status, user, vendor_lead_code, source_id, list_id, gmt_offset_now, called_since_last_reset, phone_code, phone_number, title, first_name, middle_initial, last_name, address1, address2, address3, city, state, province, postal_code, country_code, gender, date_of_birth, alt_phone, email, security_phrase, comments, rank, owner)
LOAD DATA LOCAL INFILE '$CONTAINER_CSV' 
INTO TABLE vicidial_list 
FIELDS TERMINATED BY ',' 
ENCLOSED BY '"' 
LINES TERMINATED BY '\n' 
IGNORE 1 LINES
(lead_id, entry_date, modify_date, status, user, vendor_lead_code, source_id, list_id, gmt_offset_now, called_since_last_reset, phone_code, phone_number, title, first_name, middle_initial, last_name, address1, address2, address3, city, state, province, postal_code, country_code, gender, date_of_birth, alt_phone, email, security_phrase, comments, rank, owner);

-- Force all loaded leads to list 9001 (just in case CSV has mixed IDs)
UPDATE vicidial_list SET list_id = '9001' WHERE list_id IN ('9001', '9002') OR list_id = '';

-- Ensure we have California leads (Safety check)
SELECT count(*) FROM vicidial_list WHERE list_id='9001' AND state='CA';
EOF

# Execute SQL in container
echo "Executing database setup..."
docker exec -i vicidial mysql -ucron -p1234 --local-infile=1 < /tmp/setup_db.sql > /tmp/db_setup_output.txt

# Capture initial count of CA leads
INITIAL_CA_COUNT=$(grep -o '[0-9]\+' /tmp/db_setup_output.txt | tail -1)
echo "$INITIAL_CA_COUNT" > /tmp/initial_ca_count.txt
echo "Initial CA leads in List 9001: $INITIAL_CA_COUNT"

# 2. Prepare Browser
echo "Preparing Firefox..."
VICIDIAL_ADMIN_URL="${VICIDIAL_ADMIN_URL:-http://localhost/vicidial/admin.php}"

# Restart Firefox to clear sessions/history
pkill -f firefox 2>/dev/null || true
sleep 2

# Launch Firefox
su - ga -c "DISPLAY=:1 firefox '$VICIDIAL_ADMIN_URL' > /dev/null 2>&1 &"

# Wait for window
wait_for_window "firefox\|mozilla" 30

# Focus and maximize
focus_firefox
maximize_active_window

# Handle Login
echo "Logging in..."
sleep 3
DISPLAY=:1 xdotool type "6666"
DISPLAY=:1 xdotool key Tab
DISPLAY=:1 xdotool type "andromeda"
DISPLAY=:1 xdotool key Return

# Wait for login to complete
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="