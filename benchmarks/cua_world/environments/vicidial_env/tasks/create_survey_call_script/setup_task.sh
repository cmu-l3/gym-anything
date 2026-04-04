#!/bin/bash
set -e
echo "=== Setting up create_survey_call_script task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Vicidial is running
vicidial_ensure_running

# Wait for MySQL to be fully ready
echo "Waiting for MySQL..."
for i in {1..30}; do
    if docker exec vicidial mysql -ucron -p1234 -D asterisk -e "SELECT 1;" >/dev/null 2>&1; then
        echo "MySQL is ready"
        break
    fi
    sleep 2
done

# CLEAN STATE: Remove the script if it already exists
echo "Cleaning up any existing script with ID NPS_TELECOM_2025..."
docker exec vicidial mysql -ucron -p1234 -D asterisk -e \
    "DELETE FROM vicidial_scripts WHERE script_id='NPS_TELECOM_2025';" 2>/dev/null || true

# Record initial script count (for anti-gaming check)
INITIAL_COUNT=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -sN -e \
    "SELECT COUNT(*) FROM vicidial_scripts;" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_script_count.txt
echo "Initial script count: $INITIAL_COUNT"

# Ensure Firefox is closed then open to Admin page
pkill -f firefox 2>/dev/null || true
sleep 2

VICIDIAL_ADMIN_URL="http://localhost/vicidial/admin.php"
echo "Launching Firefox at $VICIDIAL_ADMIN_URL..."
su - ga -c "DISPLAY=:1 firefox '$VICIDIAL_ADMIN_URL' > /tmp/firefox_vicidial.log 2>&1 &"

# Wait for Firefox window
wait_for_window "firefox\|mozilla\|vicidial" 45

# Maximize and focus
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i 'firefox\|mozilla\|vicidial' | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="