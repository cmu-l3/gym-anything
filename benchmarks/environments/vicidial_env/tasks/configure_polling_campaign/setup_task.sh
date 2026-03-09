#!/bin/bash
set -e

echo "=== Setting up Configure Polling Campaign task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Vicidial is running
vicidial_ensure_running

# Wait for DB ready
echo "Waiting for Vicidial MySQL..."
for i in {1..30}; do
    if docker exec vicidial mysql -ucron -p1234 -D asterisk -e "SELECT 1;" >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

echo "Cleaning up previous state..."

# SQL commands to clean state (using cron user which has permissions in this env)
DB_CMD="docker exec vicidial mysql -ucron -p1234 -D asterisk -e"

# 1. Remove Campaign SENPOLL if exists
$DB_CMD "DELETE FROM vicidial_campaigns WHERE campaign_id='SENPOLL';" 2>/dev/null || true
$DB_CMD "DELETE FROM vicidial_campaign_statuses WHERE campaign_id='SENPOLL';" 2>/dev/null || true

# 2. Remove Script SENPOLLSC if exists
$DB_CMD "DELETE FROM vicidial_scripts WHERE script_id='SENPOLLSC';" 2>/dev/null || true

# 3. Reset List 9001 (Ensure it exists, but unassign from any campaign)
# Check if list exists first, if not, create placeholder (though env usually has it)
LIST_EXISTS=$($DB_CMD "SELECT count(*) FROM vicidial_lists WHERE list_id='9001';" -N)
if [ "$LIST_EXISTS" -eq "0" ]; then
    echo "Creating List 9001..."
    $DB_CMD "INSERT INTO vicidial_lists (list_id, list_name, campaign_id, active) VALUES ('9001', 'US Senators 2026', '', 'Y');"
else
    echo "Resetting List 9001..."
    $DB_CMD "UPDATE vicidial_lists SET campaign_id='' WHERE list_id='9001';"
fi

# 4. Record initial counts for verification
$DB_CMD "SELECT count(*) FROM vicidial_campaigns;" -N > /tmp/initial_campaign_count.txt
$DB_CMD "SELECT count(*) FROM vicidial_scripts;" -N > /tmp/initial_script_count.txt

# 5. Launch Firefox
echo "Launching Firefox..."
pkill -f firefox 2>/dev/null || true

# Vicidial Admin URL
ADMIN_URL="http://localhost/vicidial/admin.php"

# Launch firefox
su - ga -c "DISPLAY=:1 firefox '$ADMIN_URL' > /dev/null 2>&1 &"

# Wait for window
wait_for_window "firefox\|mozilla" 30
maximize_active_window

# Handle Basic Auth (User: 6666, Pass: andromeda)
sleep 3
echo "Handling potential Basic Auth..."
DISPLAY=:1 xdotool type --delay 50 "6666"
sleep 0.5
DISPLAY=:1 xdotool key Tab
sleep 0.5
DISPLAY=:1 xdotool type --delay 50 "andromeda"
sleep 0.5
DISPLAY=:1 xdotool key Return

# Wait for page load
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="