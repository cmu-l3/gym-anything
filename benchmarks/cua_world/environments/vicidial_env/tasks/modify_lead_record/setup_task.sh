#!/bin/bash
set -e

echo "=== Setting up modify_lead_record task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 2. Ensure Vicidial is running
vicidial_ensure_running

# 3. Prepare Data
# Create List 9001 if it doesn't exist
echo "Creating/Resetting list 9001..."
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "DELETE FROM vicidial_lists WHERE list_id='9001';" 2>/dev/null || true
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "DELETE FROM vicidial_list WHERE list_id='9001';" 2>/dev/null || true

docker exec vicidial mysql -ucron -p1234 -D asterisk -e "
  INSERT IGNORE INTO vicidial_lists
    (list_id, list_name, campaign_id, active, list_description)
  VALUES
    ('9001', 'US Senators 2026', 'TESTCAMP', 'Y', 'US Senate office contacts');"

# Import leads from CSV (using standard loader inside container)
CSV_HOST_PATH="/home/ga/Documents/VicidialData/us_senators_vicidial_standard_format_list9001_2026-02-14.csv"
if [ ! -f "$CSV_HOST_PATH" ]; then
    # Fallback copy from assets if not present in Documents
    mkdir -p /home/ga/Documents/VicidialData
    cp /workspace/assets/us_senators_vicidial_standard_format_list9001_2026-02-14.csv "$CSV_HOST_PATH"
    chown ga:ga "$CSV_HOST_PATH"
fi

echo "Importing leads..."
docker cp "$CSV_HOST_PATH" vicidial:/tmp/senators_import.csv
docker exec vicidial /usr/share/astguiclient/VICIDIAL_lead_loader.pl \
    --forcelistid=9001 --format=standard \
    --file=/tmp/senators_import.csv > /tmp/lead_loader.log 2>&1 || true

# 4. Select Target Lead and Save Phone Number
# We pick the first lead in the list to be the target
TARGET_PHONE=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -sN -e "
  SELECT phone_number FROM vicidial_list
  WHERE list_id='9001' ORDER BY lead_id ASC LIMIT 1;" 2>/dev/null)

if [ -z "$TARGET_PHONE" ]; then
    echo "ERROR: No leads found in list 9001 after import."
    exit 1
fi

echo "$TARGET_PHONE" > /home/ga/Documents/VicidialData/target_lead_phone.txt
chown ga:ga /home/ga/Documents/VicidialData/target_lead_phone.txt
echo "Target lead phone: $TARGET_PHONE"

# 5. Capture Initial State (Hidden)
# We save the full record to verify collateral damage later
docker exec vicidial mysql -ucron -p1234 -D asterisk -sN -e "
  SELECT * FROM vicidial_list
  WHERE phone_number='$TARGET_PHONE' AND list_id='9001'
  LIMIT 1;" > /tmp/initial_lead_state_dump.txt

# 6. Setup Firefox
pkill -f firefox 2>/dev/null || true
sleep 2

# Start Firefox at Admin Login
# (Vicidial uses Basic Auth, passing credentials in URL for setup convenience, 
# but task description gives credentials to agent)
VICIDIAL_URL="http://localhost/vicidial/admin.php"

su - ga -c "DISPLAY=:1 firefox '$VICIDIAL_URL' > /tmp/firefox_setup.log 2>&1 &"

# Wait for window
wait_for_window "firefox\|mozilla\|vicidial" 30
focus_firefox
maximize_active_window

# 7. Take Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="